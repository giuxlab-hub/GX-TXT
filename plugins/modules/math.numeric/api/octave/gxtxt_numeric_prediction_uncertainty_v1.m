% Pointwise propagation through the existing native model/Jacobian evaluator.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_prediction_uncertainty_v1(model,X,plan,options)
  if(!isstruct(plan)||!isscalar(plan)||!isfield(plan,'api_id')||!strcmp(plan.api_id,'STATISTICAL_PREDICTION_INFERENCE_PLAN_v1')||plan.api_version!=1||!strcmp(plan.status,'value'))
    error('GXTXT:Numeric:PredictionInference','An eligible public CORE prediction inference plan is required');
  endif
  inference=plan.parameter_plan;
  if(!strcmp(inference.api_id,'STATISTICAL_PARAMETER_INFERENCE_PLAN_v1')||inference.api_version!=1||!strcmp(inference.status,'value')||!strcmp(inference.interval_status,'value')||!any(strcmp(plan.kind,{'mean_confidence','new_observation'})))
    error('GXTXT:Numeric:PredictionInference','Prediction plan has no eligible parameter inference');
  endif
  p=plan.all_parameter_values(:);free=plan.free_parameter_indices(:);ids=plan.all_parameter_ids;
  if(!isnumeric(p)||!isreal(p)||isempty(p)||numel(p)>128||any(!isfinite(p))||!iscellstr(ids)||numel(ids)!=numel(p)||numel(unique(ids))!=numel(ids)||!isnumeric(free)||isempty(free)||any(free!=fix(free))||any(free<1)||any(free>numel(p))||numel(unique(free))!=numel(free))
    error('GXTXT:Numeric:PredictionInference','Invalid parameter identities or free-coordinate indices');
  endif
  if(!isequal(reshape(ids(free),1,[]),reshape(inference.parameter_ids,1,[]))||!isequal(p(free),inference.source_parameters(:)))
    error('GXTXT:Numeric:PredictionInference','Free coefficient identities or values differ from their covariance plan');
  endif
  captured_callback=isstruct(model)&&isscalar(model)&&isfield(model,'kind')&&strcmp(model.kind,'registered_callback_evaluation');
  if(!captured_callback),model=gxtxt_numeric_fit_model_v1(model,numel(p));endif
  if(!isfield(model,'parameters')||!isfield(model,'parameter_ids')||!isequal(reshape(model.parameter_ids,1,[]),reshape(ids,1,[]))||numel(model.parameters)!=numel(p))
    error('GXTXT:Numeric:PredictionInference','Prediction model parameter identities differ from the fitted model');
  endif
  actual=model.parameters(:);
  if(any(!isfinite(actual))||any(abs(actual-p)>4*eps.*max(abs(actual),abs(p))))
    error('GXTXT:Numeric:PredictionInference','Prediction model parameters differ from the captured fitted values');
  endif
  if(!isnumeric(X)||!isreal(X)||ndims(X)!=2||isempty(X)||any(!isfinite(X(:))))
    error('GXTXT:Numeric:PredictionInference','Prediction coordinates must be finite and real');
  endif
  predictor_count=1;if(isfield(model,'predictor_ids')),predictor_count=numel(model.predictor_ids);if(ischar(model.predictor_ids)),predictor_count=1;endif;endif
  if(predictor_count==1&&isvector(X)),X=X(:);endif
  if(captured_callback)
    % The live callback was evaluated by the Numeric owner in its supervised
    % language lifetime. Reuse this propagation implementation; do not compile
    % a fictitious native expression or infer statistics in the caller.
    required={'schema_version','source_sha256','binding_sha256','evaluation_query','predicted','jacobian','jacobian_method'};
    if(!all(isfield(model,required))||model.schema_version!=1||columns(X)!=1||!strcmp(model.jacobian_method,'bounded_central_finite_difference'))
      error('GXTXT:Numeric:PredictionInference','Invalid captured registered callback evaluation contract');
    endif
    if(!isnumeric(model.evaluation_query)||!isreal(model.evaluation_query)||!isequal(model.evaluation_query(:),X(:))||numel(model.evaluation_query)!=rows(X)|| ...
       !isnumeric(model.predicted)||!isreal(model.predicted)||!isequal(size(model.predicted),[rows(X),1])||any(!isfinite(model.predicted(:)))|| ...
       !isnumeric(model.jacobian)||!isreal(model.jacobian)||!isequal(size(model.jacobian),[rows(X),numel(p)])||any(!isfinite(model.jacobian(:))))
      error('GXTXT:Numeric:PredictionInference','Captured callback query, response or Jacobian differs from its declared shape');
    endif
    if(!ischar(model.source_sha256)||isempty(regexp(model.source_sha256,'^[0-9a-f]{64}$','once'))|| ...
       !ischar(model.binding_sha256)||isempty(regexp(model.binding_sha256,'^[0-9a-f]{64}$','once'))||isempty(plan.model_source_sha256)||isempty(plan.model_binding_sha256))
      error('GXTXT:Numeric:PredictionInference','Registered callback propagation requires exact source and declaration identity');
    endif
    compiled=struct('source_sha256',model.source_sha256,'binding_sha256',model.binding_sha256,'predictor_ids',{{'predictor'}});
  else
    [unused,compiled]=gxtxt_numeric_fit_program_v1(model,columns(X),numel(p));
  endif
  if(!isempty(plan.model_source_sha256)||!isempty(plan.model_binding_sha256))
    if(!strcmp(compiled.source_sha256,plan.model_source_sha256)||!strcmp(compiled.binding_sha256,plan.model_binding_sha256))
      error('GXTXT:Numeric:PredictionInference','Prediction formula or bindings differ from the fitted model');
    endif
  else
    switch(inference.source_model_id)
      case 'math.numeric.linear',expected=struct('expression','intercept+slope*x','parameter_ids',{{'intercept','slope'}});
      case 'math.numeric.linear_origin',expected=struct('expression','slope*x','parameter_ids',{{'slope'}});
      case 'math.numeric.polynomial',expected=struct('kind','polynomial_fit');
      case 'math.numeric.exponential',expected=struct('kind','exponential');
      case 'math.numeric.power_law',expected=struct('kind','power_law');
      case 'math.numeric.gaussian',expected=struct('kind','gaussian');
      otherwise,error('GXTXT:Numeric:PredictionInference','Fitted model source identity is unavailable');
    endswitch
    [unused,expected]=gxtxt_numeric_fit_program_v1(expected,columns(X),numel(p));
    if(!strcmp(compiled.source_sha256,expected.source_sha256)||!strcmp(compiled.binding_sha256,expected.binding_sha256))
      error('GXTXT:Numeric:PredictionInference','Prediction formula differs from the registered fitted model');
    endif
  endif
  n=rows(X);if(n*8>512*1024*1024),error('GXTXT:Numeric:Memory','Prediction vector exceeds the 512 MiB buffer budget');endif
  if(!isstruct(options)||!isscalar(options)||any(!ismember(fieldnames(options),{'prediction_sigma','prediction_weights'})))
    error('GXTXT:Numeric:PredictionInference','Only declared future-observation sigma or relative precision is accepted');
  endif
  observation_scale=zeros(n,1);
  if(strcmp(plan.kind,'mean_confidence'))
    if(!isempty(fieldnames(options))||!strcmp(plan.observation_noise_policy,'none')),error('GXTXT:Numeric:PredictionInference','Mean confidence does not include future-observation noise');endif
  else
    switch(plan.observation_noise_policy)
      case 'explicit_absolute_sigma'
        if(!isfield(options,'prediction_sigma')||isfield(options,'prediction_weights')),error('GXTXT:Numeric:PredictionInference','Known-noise prediction requires explicit future-observation sigma');endif
        observation_scale=positive_rows(options.prediction_sigma,n,'prediction_sigma');
      case 'explicit_relative_precision'
        if(!isfield(options,'prediction_weights')||isfield(options,'prediction_sigma')),error('GXTXT:Numeric:PredictionInference','Relative-weight prediction requires explicit future-observation relative precision');endif
        observation_scale=positive_scale(plan.observation_scale)./sqrt(positive_rows(options.prediction_weights,n,'prediction_weights'));
      case 'homoscedastic_training_scale'
        if(!isempty(fieldnames(options))),error('GXTXT:Numeric:PredictionInference','Unweighted homoscedastic prediction uses its captured training scale');endif
        observation_scale(:)=positive_scale(plan.observation_scale);
      otherwise,error('GXTXT:Numeric:PredictionInference','Unknown future-observation noise policy');
    endswitch
  endif
  C=inference.source_covariance;count=numel(free);evaluation_model=model;coordinate_space='fitted_parameter_coordinates';
  if(isfield(plan,'propagation_basis'))
    basis=plan.propagation_basis;
    if(!strcmp(inference.source_model_id,'math.numeric.polynomial')||count!=numel(p)||columns(X)!=1||!isstruct(basis)||!isscalar(basis)||!strcmp(basis.api_id,'STATISTICAL_POLYNOMIAL_PROPAGATION_BASIS_v1')||basis.api_version!=1||!strcmp(basis.kind,'centered_scaled_descending_power'))
      error('GXTXT:Numeric:PredictionInference','Scaled propagation requires the captured polynomial basis');
    endif
    if(!isnumeric(basis.source_parameters)||!isreal(basis.source_parameters)||numel(basis.source_parameters)!=numel(p)||any(!isfinite(basis.source_parameters(:)))||!isnumeric(basis.query_center)||!isreal(basis.query_center)||!isscalar(basis.query_center)||!isfinite(basis.query_center))
      error('GXTXT:Numeric:PredictionInference','Invalid polynomial propagation coordinates');
    endif
    positive_scale(basis.query_scale);
    evaluation_model=gxtxt_numeric_fit_model_v1(struct('kind','polynomial_fit','parameters',basis.source_parameters),numel(p));
    C=basis.source_covariance;coordinate_space='centered_scaled_descending_power';
  elseif(strcmp(inference.source_model_id,'math.numeric.polynomial')&&!(isfield(plan,'fit_geometry')&&strcmp(plan.fit_geometry,'orthogonal_xy')&&isfield(model,'input_contract')&&strcmp(model.input_contract.fit_geometry,'orthogonal_xy')))
    error('GXTXT:Numeric:PredictionInference','Polynomial prediction requires captured scaled fit coordinates');
  endif
  if(!isnumeric(C)||!isreal(C)||!isequal(size(C),[count,count])||any(!isfinite(C(:)))||any(diag(C)<=0)),error('GXTXT:Numeric:PredictionInference','Invalid free-parameter covariance');endif
  se=sqrt(diag(C));R=bsxfun(@rdivide,bsxfun(@rdivide,C,se),se');
  if(norm(R-R','inf')>1e-10),error('GXTXT:Numeric:PredictionInference','Parameter covariance is not symmetric');endif
  [V,D]=eig((R+R')/2);eigenvalues=diag(D);roundoff=64*eps*max(1,max(abs(eigenvalues)));
  if(min(eigenvalues)<-roundoff),error('GXTXT:Numeric:PredictionInference','Parameter covariance is not positive semidefinite');endif
  root=bsxfun(@times,se,V)*diag(sqrt(max(eigenvalues,0)));
  critical=plan.critical_value;reused=!isempty(critical);
  if(!reused)
    confidence=inference.confidence;
    if(!isscalar(confidence)||!isfinite(confidence)||confidence<=0||confidence>=1),error('GXTXT:Numeric:PredictionInference','Invalid confidence level');endif
    if(strcmp(inference.distribution,'normal')),critical=-sqrt(2)*erfcinv(1+confidence);
    elseif(strcmp(inference.distribution,'student_t')),critical=gxtxt_numeric_v1('student_t_quantile',(1+confidence)/2,inference.degrees_of_freedom).values;
    else,error('GXTXT:Numeric:PredictionInference','Unsupported conditional interval distribution');endif
  endif
  if(!isnumeric(critical)||!isscalar(critical)||!isreal(critical)||!isfinite(critical)||critical<=0),error('GXTXT:Numeric:PredictionInference','Invalid interval critical value');endif
  predicted=zeros(n,1);mean_se=zeros(n,1);blocks=0;
  for first=1:4096:n
    selected=first:min(first+4095,n);
    evaluation_query=X(selected,:);
    if(isfield(plan,'propagation_basis')),evaluation_query=(evaluation_query-basis.query_center)/basis.query_scale;endif
    if(captured_callback)
      evaluated=struct('predicted',model.predicted(selected,:),'jacobian',model.jacobian(selected,:));
    else
      evaluated=gxtxt_numeric_nonlinear_evaluate_v1(evaluation_model,evaluation_query,struct('jacobian',true));
    endif
    if(columns(evaluated.predicted)!=1),error('GXTXT:Numeric:PredictionInference','Scalar prediction plans require one response component');endif
    predicted(selected)=evaluated.predicted;
    Z=evaluated.jacobian(:,free)*root;maximum=max(abs(Z),[],2);active=maximum>0;
    scale=zeros(numel(selected),1);scale(active)=maximum(active).*sqrt(sum(bsxfun(@rdivide,Z(active,:),maximum(active)).^2,2));
    mean_se(selected)=scale;blocks+=1;
  endfor
  total_se=hypot(mean_se,observation_scale);margin=critical*total_se;
  lower=predicted-margin;upper=predicted+margin;valid=isfinite(lower)&isfinite(upper)&isfinite(total_se);
  lower(!valid)=NaN;upper(!valid)=NaN;
  available=sum(valid);
  evaluation_blocks=blocks;maximum_jacobian_rows=min(n,4096);
  if(captured_callback),evaluation_blocks=1;maximum_jacobian_rows=n;endif
  out=struct('numeric_api','NUMERIC_API_v1','operation','prediction_uncertainty','plan',plan, ...
    'predicted',predicted,'mean_standard_error',mean_se,'observation_standard_deviation',observation_scale, ...
    'standard_error',total_se,'lower',lower,'upper',upper,'bounds_available',double(valid),'query_index',(1:n)', ...
    'query_count',n,'available_count',available,'unavailable_count',n-available,'critical_value',critical,'critical_value_reused',reused,'covariance_roundoff_eigenvalues_clipped',sum(eigenvalues<0), ...
    'model_source_sha256',compiled.source_sha256,'model_binding_sha256',compiled.binding_sha256, ...
    'parameter_ids',{model.parameter_ids},'predictor_ids',{compiled.predictor_ids},'propagation_coordinate_space',coordinate_space,'evaluation_blocks',evaluation_blocks,'maximum_jacobian_rows',maximum_jacobian_rows);
  if(captured_callback),out.model_evaluation_kind='registered_callback';endif
endfunction
function result=positive_rows(value,n,name)
  if(!isnumeric(value)||!isreal(value)||!isvector(value)||any(!isfinite(value))||any(value<=0)||!any(numel(value)==[1,n]))
    error('GXTXT:Numeric:PredictionInference','%s must be positive finite scalar or one value per query',name);
  endif
  result=value(:);if(isscalar(result)),result=repmat(result,n,1);endif
endfunction
function result=positive_scale(value)
  if(!isnumeric(value)||!isscalar(value)||!isreal(value)||!isfinite(value)||value<=0),error('GXTXT:Numeric:PredictionInference','Captured noise scale must be positive and finite');endif
  result=value;
endfunction
