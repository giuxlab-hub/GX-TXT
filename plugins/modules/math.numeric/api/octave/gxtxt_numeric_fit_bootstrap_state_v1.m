% SPDX-License-Identifier: GPL-3.0-or-later
% Shared data-only bootstrap preparation, draws and summary. Both refit drivers
% use these same numerical owners; callback execution stays in its Script Job.
function out=gxtxt_numeric_fit_bootstrap_state_v1(action,varargin)
  switch(action)
    case 'prepare',out=prepare(varargin{:});
    case 'draw',out=draw_sample(varargin{:});
    case 'summarize',out=summarize(varargin{:});
    otherwise,error('GXTXT:Numeric:Bootstrap','Unknown bootstrap state operation');
  endswitch
endfunction
function out=prepare(model,X,y,plan,options)
  if(!isstruct(plan)||!isscalar(plan)||!strcmp(field(plan,'api_id',''),'STATISTICAL_FIT_BOOTSTRAP_PLAN_v1')||field(plan,'api_version',0)!=1||!strcmp(field(plan,'status',''),'value'))
    error('GXTXT:Numeric:Bootstrap','An eligible public CORE bootstrap plan is required');
  endif
  if(!isstruct(options)||!isscalar(options)||any(!strcmp(fieldnames(options),'weights'))),error('GXTXT:Numeric:Bootstrap','Bootstrap input options accept only the original positive precision weights');endif
  operation=plan.source_operation;method=plan.method;
  if(!any(strcmp(operation,{'least_squares','linear_regression','polynomial_fit','nonlinear_fit'}))||!any(strcmp(method,{'pairs','residual','parametric_gaussian'}))||!strcmp(plan.interval_method,'percentile')||!strcmp(plan.interval_policy,'all_requested_regular_converged'))
    error('GXTXT:Numeric:Bootstrap','Unsupported bootstrap method, fit operation or interval policy');
  endif
  n=integer(plan.n,2,1000000,'row count');p=integer(plan.p,1,128,'parameter count');free=integer(plan.free_parameter_count,1,p,'free parameter count');
  reps=integer(plan.replicates,20,10000,'replicate count');seed=integer(plan.seed,1,2147483646,'seed');
  confidence=real_scalar(plan.confidence,'confidence');limit=real_scalar(plan.max_seconds,'time budget');
  if(confidence<=0||confidence>=1||limit<=0||limit>3600||plan.rank!=free||!strcmp(plan.generator,'park_miller_16807_v1')||!strcmp(plan.normal_transform,'box_muller_pairs_v1')||!strcmp(plan.execution_policy,'sequential_one_thread_per_refit'))
    error('GXTXT:Numeric:Bootstrap','Invalid inference, rank or random/execution contract');
  endif
  if(!isnumeric(X)||!isreal(X)||ndims(X)!=2||isempty(X)||any(!isfinite(X(:)))||!isnumeric(y)||!isreal(y)||!isvector(y)||numel(y)!=n||any(!isfinite(y(:))))
    error('GXTXT:Numeric:Bootstrap','Bootstrap needs the exact finite retained predictor/response rows');
  endif
  if(!strcmp(operation,'least_squares')&&isvector(X)),X=X(:);endif
  if(rows(X)!=n||columns(X)>128),error('GXTXT:Numeric:Bootstrap','Predictor shape differs from the captured source');endif
  workspace=80*n*p+160*n+32*reps*p+64*p*p+16*numel(X);
  if(n*reps>10000000||n*p*reps>128000000||workspace>536870912),error('GXTXT:Numeric:Bootstrap','Bootstrap exceeds its up-front draw/work/512-MiB workspace budget');endif
  X=double(X);y=double(y(:));parameters=plan.source_parameters(:);
  if(!isnumeric(parameters)||!isreal(parameters)||numel(parameters)!=p||any(!isfinite(parameters))||!iscellstr(plan.parameter_ids)||numel(plan.parameter_ids)!=p||numel(unique(plan.parameter_ids))!=p||!iscellstr(plan.parameter_roles)||numel(plan.parameter_roles)!=p)
    error('GXTXT:Numeric:Bootstrap','Invalid captured parameter values, identities or roles');
  endif
  fixed=strcmp(plan.parameter_roles(:),'fixed');
  if(sum(!fixed)!=free||any(!ismember(plan.parameter_roles,{'fixed','free'}))),error('GXTXT:Numeric:Bootstrap','Parameter roles differ from the captured free count');endif
  semantics=plan.weight_semantics;w=field(options,'weights',[]);
  if(isempty(w))
    if(!strcmp(semantics,'unweighted')),error('GXTXT:Numeric:Bootstrap','Supply the original retained precision weights');endif
    w=ones(n,1);
  endif
  if(!isnumeric(w)||!isreal(w)||!isvector(w)||numel(w)!=n||any(!isfinite(w(:)))||any(w(:)<=0)||!any(strcmp(semantics,{'unweighted','relative','inverse_variance'})))
    error('GXTXT:Numeric:Bootstrap','Original precision weights must be finite, positive and aligned');
  endif
  w=double(w(:));if(strcmp(semantics,'unweighted')&&any(w!=1)),error('GXTXT:Numeric:Bootstrap','An unweighted source cannot acquire new weights');endif
  signature=gxtxt_numeric_v1('fit_observation_signature',y,w,[],X);
  for name={'response_sha256','weights_sha256','predictors_sha256'}
    if(!strcmp(signature.(name{1}),plan.observation_signature.(name{1}))),error('GXTXT:Numeric:Bootstrap','Response or precision rows differ from the original fitted observations');endif
  endfor
  if(!isstruct(model)||!isscalar(model)||!isfield(model,'parameters')||!isequal(model.parameters(:),parameters)),error('GXTXT:Numeric:Bootstrap','The fitted model parameters differ from the captured CORE plan');endif
  [model,prediction]=reference_model(operation,model,X,plan);
  if(numel(prediction)!=n||any(!isfinite(prediction))),error('GXTXT:Numeric:Bootstrap','Captured model does not evaluate to finite scalar responses');endif
  policy=plan.solver_policy;
  if(!isstruct(policy)||!isscalar(policy)),error('GXTXT:Numeric:Bootstrap','Captured solver policy must be a scalar struct');endif
  policy.loss=field(policy,'loss','linear');
  if(!strcmp(field(model,'kind',''),'registered_callback_evaluation')),policy.threads=1;policy.nonfinite='error';endif
  if(!strcmp(method,'pairs')&&!strcmp(policy.loss,'linear')),error('GXTXT:Numeric:Bootstrap','Residual/Gaussian simulation requires ordinary least-squares loss');endif
  if(!strcmp(field(model,'kind',''),'registered_callback_evaluation'))
    policy.weight_semantics=semantics_option(semantics);policy.required_measurement_input='none';
    if(!strcmp(semantics,'unweighted')),policy.required_measurement_input='weights';endif
  endif
  pool=[];simulation_scale=NaN;
  switch(method)
    case 'pairs'
      if(!strcmp(plan.simulation_scale_policy,'aligned_case_triplets')),error('GXTXT:Numeric:Bootstrap','Case resampling plan differs from its numeric operation');endif
    case 'residual'
      if(strcmp(semantics,'inverse_variance')||!strcmp(plan.simulation_scale_policy,'centered_weighted_residuals_captured_scale')),error('GXTXT:Numeric:Bootstrap','Residual resampling needs its explicit relative-scale plan');endif
      simulation_scale=real_scalar(plan.residual_scale,'captured residual scale');
      pool=sqrt(w).*(y-prediction);pool-=mean(pool);pool_scale=norm(pool)/sqrt(n);
      if(simulation_scale<=0||!isfinite(pool_scale)||pool_scale<=0),error('GXTXT:Numeric:Bootstrap','Residual pool or captured noise scale is degenerate');endif
      pool=(pool/pool_scale)*simulation_scale;
    case 'parametric_gaussian'
      if(strcmp(plan.simulation_scale_policy,'gaussian_absolute_precision')&&strcmp(semantics,'inverse_variance')&&strcmp(plan.noise_model,'independent_gaussian_known_sigma'))
        simulation_scale=1;
      elseif(strcmp(plan.simulation_scale_policy,'gaussian_estimated_relative_scale')&&any(strcmp(semantics,{'unweighted','relative'}))&&strcmp(plan.noise_model,'independent_gaussian_estimated_variance'))
        simulation_scale=real_scalar(plan.residual_scale,'captured residual scale');
      else error('GXTXT:Numeric:Bootstrap','Gaussian resampling lacks its explicit matching noise model');endif
      if(simulation_scale<=0),error('GXTXT:Numeric:Bootstrap','Gaussian simulation requires a positive captured noise scale');endif
  endswitch
  out=struct('schema','gxtxt.fit_bootstrap_state.v1','plan',plan,'model',model,'predictors',X,'response',y,'weights',w,'prediction',prediction,'parameters',parameters,'fixed_mask',fixed,'solver_policy',policy,'residual_pool',pool,'simulation_scale',simulation_scale,'observation_signature',signature,'workspace_bytes_bound',workspace);
endfunction
function state=check_state(state)
  if(!isstruct(state)||!isscalar(state)||!strcmp(field(state,'schema',''),'gxtxt.fit_bootstrap_state.v1')||!isstruct(state.plan)||!strcmp(state.plan.api_id,'STATISTICAL_FIT_BOOTSTRAP_PLAN_v1')||!strcmp(state.plan.status,'value'))
    error('GXTXT:Numeric:Bootstrap','Use the unchanged prepared public bootstrap state');
  endif
  n=integer(state.plan.n,2,1000000,'row count');p=integer(state.plan.p,1,128,'parameter count');r=integer(state.plan.replicates,20,10000,'replicate count');
  if(n*r>10000000||n*p*r>128000000||state.workspace_bytes_bound>536870912||rows(state.predictors)!=n||columns(state.predictors)>128||numel(state.response)!=n||numel(state.weights)!=n||numel(state.prediction)!=n||numel(state.parameters)!=p||numel(state.fixed_mask)!=p)
    error('GXTXT:Numeric:Bootstrap','Prepared bootstrap shape/work budget changed');
  endif
endfunction
function out=draw_sample(prepared,seed)
  prepared=check_state(prepared);plan=prepared.plan;state=integer(seed,1,2147483646,'seed');
  X=prepared.predictors;y=prepared.response;w=prepared.weights;prediction=prepared.prediction;pool=prepared.residual_pool;simulation_scale=prepared.simulation_scale;n=plan.n;method=plan.method;
      if(strcmp(method,'parametric_gaussian'))
        draw=gxtxt_numeric_v1('resample_indices',2147483646,2*ceil(n/2),1,state);state=draw.next_seed;
        u=reshape(draw.indices/2147483647,2,[]);
        radius=sqrt(-2*log(u(1,:)));angle=2*pi*u(2,:);
        normal=reshape([radius.*cos(angle);radius.*sin(angle)],[],1);
        localX=X;localY=prediction+simulation_scale*(normal(1:n)./sqrt(w));localW=w;
      else
        draw=gxtxt_numeric_v1('resample_indices',n,n,1,state);state=draw.next_seed;index=draw.indices(:);
        if(strcmp(method,'pairs')),localX=X(index,:);localY=y(index);localW=w(index);
        else localX=X;localY=prediction+pool(index)./sqrt(w);localW=w;endif
      endif
  out=struct('predictors',localX,'response',localY,'weights',localW,'seed',seed,'next_seed',state);
endfunction
function out=summarize(prepared,samples,status,seeds,execution)
  prepared=check_state(prepared);plan=prepared.plan;n=plan.n;p=plan.p;free=plan.free_parameter_count;reps=plan.replicates;confidence=plan.confidence;seed=plan.seed;limit=plan.max_seconds;method=plan.method;operation=plan.source_operation;semantics=plan.weight_semantics;
  parameters=prepared.parameters;signature=prepared.observation_signature;workspace=prepared.workspace_bytes_bound;simulation_scale=prepared.simulation_scale;
  if(!isnumeric(samples)||!isreal(samples)||!isequal(size(samples),[reps,p])||!isnumeric(status)||!isreal(status)||numel(status)!=reps||any(!ismember(status(:),[0,1,2,3,4,5,6,7]))||!isnumeric(seeds)||!isreal(seeds)||numel(seeds)!=reps||any(!isfinite(seeds(:)))||any(seeds(:)!=fix(seeds(:)))||any(seeds(:)<0|seeds(:)>2147483646))
    error('GXTXT:Numeric:Bootstrap','Invalid replicate ledger shapes or status codes');
  endif
  status=uint8(status(:));seeds=uint32(seeds(:));
  attempted=integer(execution.attempted_count,0,reps,'attempted count');state=integer(execution.next_seed,1,2147483646,'next seed');elapsed=real_scalar(execution.elapsed_seconds,'elapsed seconds');messages=execution.messages;
  if(elapsed<0||(!isempty(messages)&&(!iscellstr(messages)||numel(messages)>8))||any(seeds(1:attempted)==0)||any(seeds(attempted+1:end)!=0)||any(status(attempted+1:end)!=0)||any(status(1:attempted)==0)||sum(status==7)>1||(any(status==7)&&status(attempted)!=7))
    error('GXTXT:Numeric:Bootstrap','Replicate execution accounting changed');
  endif
  if(isempty(messages)),messages={};endif
  success=status==1|status==6;
  if(any(any(!isnan(samples(!success,:))))),error('GXTXT:Numeric:Bootstrap','Unsuccessful or unattempted trials must retain NaN draws');endif
  if(any(any(!isfinite(samples(success,:))))||any(any(bsxfun(@ne,samples(success,logical(prepared.fixed_mask)),parameters(logical(prepared.fixed_mask)).'))))
    error('GXTXT:Numeric:Bootstrap','Successful draws contain invalid or changed fixed parameter values');
  endif
  success=status==1|status==6;count=sum(success);covariance=NaN(p,p);lower=NaN(p,1);upper=NaN(p,1);standard_error=NaN(p,1);summary_status='insufficient_successful_replicates';summary_message='';quantile_definition='Hyndman-Fan type 7 linear interpolation';
  if(count>=2)
    try
      % Reuse the existing sample-covariance owner once, then its diagonal.
      retained=samples(success,:);
      % Covariance is translation invariant. Shift by one recorded draw before
      % the shared owner centers it, preserving exact fixed-point columns and
      % reducing cancellation for large physical coefficient offsets.
      retained=bsxfun(@minus,retained,retained(1,:));
      captured=gxtxt_numeric_advanced_v1('statistics','covariance_diagnostics',retained,[],[],struct());
      covariance=captured.covariance;standard_error=sqrt(diag(covariance));
      if(any(!isfinite(covariance(:)))||any(diag(covariance)<0)),error('GXTXT:Numeric:Bootstrap','Replicate covariance is not finitely representable');endif
      summary_status='value';
      if(all(status==1))
        for j=1:p
          q=gxtxt_numeric_v1('quantiles',samples(:,j),[(1-confidence)/2;(1+confidence)/2]);
          lower(j)=q.quantiles(1);upper(j)=q.quantiles(2);quantile_definition=q.definition;
        endfor
      endif
    catch failure
      covariance=NaN(p,p);standard_error=NaN(p,1);lower=NaN(p,1);upper=NaN(p,1);summary_status='nonfinite_summary';summary_message=failure.message(1:min(512,numel(failure.message)));
    end_try_catch
  endif
  out=struct('schema','gxtxt.fit_bootstrap_numeric.v1','method',method,'source_operation',operation,'n',n,'p',p,'free_parameter_count',free, ...
    'replicates',reps,'attempted_count',attempted,'successful_count',count,'regular_count',sum(status==1),'boundary_count',sum(status==6), ...
    'rank_failure_count',sum(status==2),'nonconverged_count',sum(status==3),'nonfinite_count',sum(status==4),'solver_error_count',sum(status==5),'not_completed_count',sum(status==0|status==7), ...
    'confidence',confidence,'seed',seed,'next_seed',state,'generator',plan.generator,'normal_transform',plan.normal_transform,'strategy_version',1, ...
    'execution_policy',plan.execution_policy,'cancellation_policy',plan.cancellation_policy,'max_seconds',limit,'elapsed_seconds',elapsed, ...
    'interval_method',plan.interval_method,'interval_policy',plan.interval_policy,'quantile_definition',quantile_definition,'tail_resolution',(reps-1)*(1-confidence)/2, ...
    'weight_semantics',semantics,'simulation_scale_policy',plan.simulation_scale_policy,'simulation_scale',simulation_scale, ...
    'observation_signature',signature,'source_parameters',parameters,'parameter_ids',{plan.parameter_ids},'source_model_sha256',plan.model_source_sha256,'source_binding_sha256',plan.model_binding_sha256, ...
    'summary_status',summary_status,'summary_message',summary_message,'messages',{messages},'parameter_covariance',covariance,'parameter_standard_errors',standard_error,'ci_lower',lower,'ci_upper',upper, ...
    'original_fit_count',0,'workspace_bytes_bound',workspace,'parameter_samples',samples,'replicate_status',status,'replicate_seed',seeds);
endfunction
function [model,prediction]=reference_model(operation,model,X,plan)
  parameters=plan.source_parameters(:);p=numel(parameters);
  if(strcmp(operation,'least_squares'))
    if(!strcmp(field(model,'kind',''),'linear_design')||columns(X)!=p),error('GXTXT:Numeric:Bootstrap','Least-squares bootstrap requires its exact original linear design');endif
    if(!isequal(reshape(field(model,'parameter_ids',{}),1,[]),reshape(plan.parameter_ids,1,[]))),error('GXTXT:Numeric:Bootstrap','Linear-design parameter identities differ from the captured fit');endif
    prediction=X*parameters;
  elseif(strcmp(operation,'linear_regression'))
    if(columns(X)!=1||!any(p==[1,2])),error('GXTXT:Numeric:Bootstrap','Invalid scalar linear design');endif
    if(p==2)
      if(!strcmp(field(model,'kind',''),'linear')||!isequal(reshape(plan.parameter_ids,1,[]),{'intercept','slope'})),error('GXTXT:Numeric:Bootstrap','Linear coefficient identity changed');endif
      prediction=parameters(1)+parameters(2)*X;
    else
      if(!strcmp(field(model,'kind',''),'linear_origin')||!isequal(reshape(plan.parameter_ids,1,[]),{'slope'})),error('GXTXT:Numeric:Bootstrap','Origin-linear coefficient identity changed');endif
      prediction=parameters(1)*X;
    endif
  elseif(strcmp(operation,'polynomial_fit'))
    if(!strcmp(field(model,'kind',''),'polynomial_fit')||columns(X)!=1||!isfield(plan,'propagation_basis')),error('GXTXT:Numeric:Bootstrap','Polynomial bootstrap needs its captured scaled basis');endif
    basis=plan.propagation_basis;
    evaluated=gxtxt_numeric_v1('polynomial_evaluate',struct('scaled_coefficients',basis.source_parameters,'x_center',basis.query_center,'x_scale',basis.query_scale),X);
    prediction=evaluated.yq;
  elseif(strcmp(field(model,'kind',''),'registered_callback_evaluation'))
    if(!strcmp(operation,'nonlinear_fit')||!isequal(reshape(model.parameter_ids,1,[]),reshape(plan.parameter_ids,1,[]))||!isequal(model.evaluation_query,X)||!strcmp(model.source_sha256,plan.model_source_sha256)||!strcmp(model.binding_sha256,plan.model_binding_sha256))
      error('GXTXT:Numeric:Bootstrap','Callback evaluation differs from the exact captured model or predictors');
    endif
    prediction=model.predicted;
  else
    model=gxtxt_numeric_fit_model_v1(model,p);
    if(!isequal(reshape(model.parameter_ids,1,[]),reshape(plan.parameter_ids,1,[]))),error('GXTXT:Numeric:Bootstrap','Declared fitted coefficient identities changed');endif
    evaluated=gxtxt_numeric_v1('nonlinear_evaluate',model,X);prediction=evaluated.predicted;
    for key={'source','binding'}
      expected=plan.(['model_',key{1},'_sha256']);
      if(!isempty(expected)&&!strcmp(evaluated.([key{1},'_sha256']),expected)),error('GXTXT:Numeric:Bootstrap','Declared model differs from the captured fitted source');endif
    endfor
  endif
  prediction=prediction(:);
endfunction
function value=semantics_option(value),if(strcmp(value,'unweighted')),value='relative';endif;endfunction
function value=field(s,key,fallback),if(isfield(s,key)),value=s.(key);else value=fallback;endif;endfunction
function value=real_scalar(value,label)
  if(!isnumeric(value)||!isreal(value)||!isscalar(value)||!isfinite(value)),error('GXTXT:Numeric:Bootstrap','%s must be a finite real scalar',label);endif
  value=double(value);
endfunction
function value=integer(value,lo,hi,label)
  value=real_scalar(value,label);if(value!=fix(value)||value<lo||value>hi),error('GXTXT:Numeric:Bootstrap','%s is outside its bounded integer range',label);endif
endfunction
