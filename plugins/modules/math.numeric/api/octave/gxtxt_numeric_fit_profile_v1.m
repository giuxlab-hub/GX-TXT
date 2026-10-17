% SPDX-License-Identifier: GPL-3.0-or-later
% Bounded constrained likelihood search; all refits use the existing Ceres owner.
function out=gxtxt_numeric_fit_profile_v1(model,X,y,plan,options)
  if(nargin<5),options=struct();endif
  if(!isstruct(plan)||!isscalar(plan)||!strcmp(field(plan,'api_id',''),'STATISTICAL_FIT_PROFILE_PLAN_v1')||field(plan,'api_version',0)!=1||!strcmp(field(plan,'status',''),'value'))
    error('GXTXT:Numeric:Profile','Use an eligible public CORE profile plan');
  endif
  if(!isstruct(options)||!isscalar(options)||any(!strcmp(fieldnames(options),'weights'))),error('GXTXT:Numeric:Profile','Only original precision weights are accepted');endif
  n=integer(plan.n,2,1000000);p=integer(plan.p,1,128);index=integer(plan.parameter_index,1,p);budget=integer(plan.max_refits,4,256);
  for key={'confidence','search_lower','search_upper','initial_step','parameter_tolerance','max_seconds','baseline_sse'}
    scalar(plan.(key{1}));
  endfor
  if(plan.confidence<=0||plan.confidence>=1||plan.max_seconds<=0||plan.max_seconds>3600||plan.initial_step<=0||plan.parameter_tolerance<=0||plan.search_lower>=plan.search_upper||plan.baseline_sse<0||n*p*budget>128000000)
    error('GXTXT:Numeric:Profile','Invalid inference/search/work budget');
  endif
  if(!isnumeric(X)||!isreal(X)||ndims(X)!=2||any(!isfinite(X(:)))||!isnumeric(y)||!isreal(y)||!isvector(y)||numel(y)!=n||any(!isfinite(y(:))))
    error('GXTXT:Numeric:Profile','Supply the exact finite retained predictors and scalar response');
  endif
  if(isvector(X)&&plan.observation_signature.predictor_count==1),X=X(:);endif
  if(rows(X)!=n||columns(X)<1||columns(X)>128),error('GXTXT:Numeric:Profile','Original predictor dimensions changed');endif
  X=double(X);y=double(y(:));w=field(options,'weights',[]);semantics=plan.weight_semantics;
  if(isempty(w)&&strcmp(semantics,'unweighted')),w=ones(n,1);endif
  if(!isnumeric(w)||!isreal(w)||!isvector(w)||numel(w)!=n||any(!isfinite(w(:)))||any(w(:)<=0)||!any(strcmp(semantics,{'unweighted','relative','inverse_variance'}))||strcmp(semantics,'unweighted')&&any(w(:)!=1))
    error('GXTXT:Numeric:Profile','Supply unchanged positive original precision weights');
  endif
  w=double(w(:));signature=gxtxt_numeric_v1('fit_observation_signature',y,w,[],X);
  for key={'response_sha256','weights_sha256','predictors_sha256'}
    if(!strcmp(signature.(key{1}),plan.observation_signature.(key{1}))),error('GXTXT:Numeric:Profile','Original observation identity changed');endif
  endfor
  q=plan.source_parameters(:);
  if(!isnumeric(q)||!isreal(q)||numel(q)!=p||any(!isfinite(q))||!isstruct(model)||!isscalar(model)||!isfield(model,'parameters')||!isequal(model.parameters(:),q))
    error('GXTXT:Numeric:Profile','Captured fitted parameters changed');
  endif
  [programs,model]=gxtxt_numeric_fit_program_v1(model,columns(X),p);
  if(numel(programs)!=1||!isequal(reshape(model.parameter_ids,1,[]),reshape(plan.parameter_ids,1,[]))||!strcmp(model.source_sha256,plan.model_source_sha256)||!strcmp(model.binding_sha256,plan.model_binding_sha256)||!strcmp(model.parameter_ids{index},plan.parameter_id))
    error('GXTXT:Numeric:Profile','Captured declared scalar model identity changed');
  endif
  policy=plan.solver_policy;fixed=policy.fixed_mask(:);lb=policy.lower_bounds(:);ub=policy.upper_bounds(:);
  if(numel(fixed)!=p||numel(lb)!=p||numel(ub)!=p||any(!ismember(fixed,[0,1]))||any(isnan(lb)|isnan(ub))||any(lb>ub)||fixed(index)||any(q<lb|q>ub)||plan.search_lower<lb(index)||plan.search_upper>ub(index)||plan.search_lower>q(index)||plan.search_upper<q(index)||!strcmp(policy.loss,'linear')||!isequal(logical(fixed),strcmp(plan.parameter_roles(:),'fixed'))||sum(!fixed)!=plan.free_parameter_count)
    error('GXTXT:Numeric:Profile','Original constraints, Gaussian objective or fixed parameters changed');
  endif
  if(strcmp(plan.objective,'delta_weighted_sse'))
    if(!strcmp(semantics,'inverse_variance')||!strcmp(plan.noise_model,'independent_gaussian_known_sigma')),error('GXTXT:Numeric:Profile','Known Gaussian scale requires absolute precisions');endif
  elseif(strcmp(plan.objective,'n_log_sse_ratio'))
    if(!any(strcmp(semantics,{'unweighted','relative'}))||!strcmp(plan.noise_model,'independent_gaussian_estimated_variance')||plan.baseline_sse<=0),error('GXTXT:Numeric:Profile','Estimated Gaussian scale requires a positive retained SSE');endif
  else error('GXTXT:Numeric:Profile','Unknown Gaussian likelihood objective');endif
  if(!strcmp(plan.threshold_distribution,'chi_square_1')||!strcmp(plan.threshold_method,'two_erfinv_confidence_squared')||!strcmp(plan.interval_policy,'connected_local_profile_component')||!strcmp(plan.execution_policy,'sequential_one_thread_per_refit')||plan.original_fit_count!=0)
    error('GXTXT:Numeric:Profile','Unknown threshold, interval or execution policy');
  endif
  workspace=80*n*p+176*n+16*numel(X)+8*budget*(p+6)+64*p*p;
  if(workspace>536870912),error('GXTXT:Numeric:Profile','Profile exceeds its 512 MiB workspace bound');endif
  % P(chi-square_1 <= t) = erf(sqrt(t/2)); exactly one Numeric quantile.
  threshold=2*erfinv(plan.confidence)^2;
  if(!isfinite(threshold)||threshold<=0),error('GXTXT:Numeric:Profile','Confidence threshold is outside finite numerical resolution');endif
  policy.threads=1;policy.nonfinite='error';policy.fit_geometry='vertical_response';policy.multistart_mode='single';policy.required_measurement_input='none';
  if(!strcmp(semantics,'unweighted')),policy.weights=w;policy.weight_semantics=semantics;policy.required_measurement_input='weights';endif
  policy.fixed_mask=fixed;policy.fixed_mask(index)=1;
  trials=NaN(budget,4);parameters=NaN(budget,p);statuses=zeros(budget,1,'uint8');messages=cell(budget,1);count=0;success=0;improved=false;clock=tic();
  endpoints=cell(1,2);
  for side=1:2
    direction=2*side-3;limit=plan.search_lower;bound=lb(index);if(side==2),limit=plan.search_upper;bound=ub(index);endif
    endpoint=make_endpoint('refit_budget',NaN,q(index),0,NaN,NaN,'Refit budget ended before a threshold or search endpoint');
    side_budget=floor(budget/2);if(side==2),side_budget=budget-count;endif
    side_start=count;inside=q(index);inside_ratio=0;outside=NaN;step=plan.initial_step;refining=false;next=q(index)+direction*min(step,abs(limit-q(index)));
    if(limit==q(index))
      if(limit==bound),endpoint=make_endpoint('constraint_bound',limit,limit,0,NaN,NaN,'Original parameter bound equals the captured estimate');
      else endpoint=make_endpoint('open_search_limit',direction*Inf,limit,0,NaN,NaN,'Search limit equals the captured estimate; this side was not explored');endif
      endpoints{side}=endpoint;continue;
    endif
    if(next==q(index)),endpoints{side}=make_endpoint('resolution_limit',NaN,q(index),0,NaN,NaN,'Initial step is below physical parameter resolution');continue;endif
    while(count-side_start<side_budget)
      remaining=plan.max_seconds-toc(clock);
      if(remaining<=0),endpoint=make_endpoint('time_budget',NaN,inside,inside_ratio,inside,outside,'Time budget ended; no completed endpoint');break;endif
      count+=1;initial=q;initial(index)=next;local=policy;local.max_seconds=min(3600,remaining);
      trials(count,1)=next;trials(count,4)=direction;
      try
        current=gxtxt_numeric_v1('nonlinear_fit',model,X,y,initial,local);
        if(!current.converged),error('GXTXT:Numeric:ProfileRefit','Constrained solver did not converge');endif
        if(numel(current.parameters)!=p||any(!isfinite(current.parameters))||current.parameters(index)!=next||any(current.parameters(logical(fixed))!=q(logical(fixed)))||!isfinite(current.sse)||current.sse<0)
          error('GXTXT:Numeric:ProfileRefit','Constrained result changed fixed values or is nonfinite');
        endif
        sse=current.sse;delta=sse-plan.baseline_sse;
        % This tolerance identifies materially lower minima, not CI coverage.
        if(delta < -1e-8*max(realmin,plan.baseline_sse))
          statuses(count)=3;improved=true;trials(count,2)=sse;parameters(count,:)=current.parameters';messages{count}='Constrained refit improved the retained baseline objective';
          endpoint=make_endpoint('baseline_improved',NaN,next,NaN,inside,outside,messages{count});break;
        endif
        if(strcmp(plan.objective,'delta_weighted_sse')),ratio=max(0,delta);else ratio=n*log1p(max(0,delta)/plan.baseline_sse);endif
        trials(count,2:3)=[sse,ratio];parameters(count,:)=current.parameters';statuses(count)=1;messages{count}='';success+=1;
      catch failure
        statuses(count)=2;messages{count}=failure.message(1:min(512,numel(failure.message)));
        endpoint=make_endpoint('solver_failure',NaN,next,NaN,inside,outside,messages{count});break;
      end_try_catch
      if(ratio>=threshold),outside=next;refining=true;else inside=next;inside_ratio=ratio;endif
      if(refining)
        if(abs(outside-inside)<=plan.parameter_tolerance)
          % The midpoint is a bracket estimate; its objective is the last actual
          % constrained trial, explicitly retained as such in the receipt.
          value=inside+(outside-inside)/2;
          endpoint=make_endpoint('threshold_crossing',value,next,ratio,inside,outside,'Endpoint is the midpoint of the retained threshold bracket; ratio belongs to the last evaluated bracket endpoint');break;
        endif
        next=inside+(outside-inside)/2;
        if(next==inside||next==outside),endpoint=make_endpoint('resolution_limit',NaN,inside,inside_ratio,inside,outside,'Physical parameter resolution prevents further bracket refinement');break;endif
      elseif(next==limit)
        if(limit==bound),status='constraint_bound';value=limit;message='Original parameter-domain bound reached below threshold';
        else status='open_search_limit';value=direction*Inf;message='No threshold crossing within finite search; global unboundedness is not proved';endif
        endpoint=make_endpoint(status,value,limit,ratio,NaN,NaN,message);break;
      else
        step=min(realmax/2,step*1.8);next=q(index)+direction*min(step,abs(limit-q(index)));
        if(next==inside),endpoint=make_endpoint('resolution_limit',NaN,inside,inside_ratio,NaN,NaN,'Initial step is below physical parameter resolution');break;endif
      endif
      endpoint=make_endpoint('refit_budget',NaN,inside,inside_ratio,inside,outside,'Refit budget ended before a completed endpoint');
    endwhile
    endpoints{side}=endpoint;
    if(improved)
      endpoints={make_endpoint('baseline_improved',NaN,q(index),NaN,NaN,NaN,'A lower baseline was discovered; review the original fit'),make_endpoint('baseline_improved',NaN,q(index),NaN,NaN,NaN,'A lower baseline was discovered; review the original fit')};break;
    endif
  endfor
  trials=trials(1:count,:);parameters=parameters(1:count,:);statuses=statuses(1:count);messages=messages(1:count);
  settings=struct();for key={'parameter_id','confidence','search_lower','search_upper','initial_step','parameter_tolerance','max_refits','max_seconds'},settings.(key{1})=plan.(key{1});endfor
  ledger=struct('trials',trials,'parameters',parameters,'status',double(statuses),'messages',{messages});
  summary=struct('schema','gxtxt.fit_profile_numeric.v1','settings',settings,'n',n,'p',p,'baseline_sse',plan.baseline_sse,'objective',plan.objective,'threshold',threshold,'threshold_distribution',plan.threshold_distribution,'threshold_method',plan.threshold_method,'interval_policy',plan.interval_policy,'execution_policy',plan.execution_policy,'original_fit_count',0,'attempted_count',count,'successful_count',success,'failed_count',count-success,'max_refits',budget,'elapsed_seconds',toc(clock),'workspace_bytes_bound',workspace,'source_parameters',q,'parameter_ids',{plan.parameter_ids},'observation_signature',signature,'source_model_sha256',model.source_sha256,'source_binding_sha256',model.binding_sha256,'lower',endpoints{1},'upper',endpoints{2},'baseline_improved',double(improved),'ledger_sha256',hash('sha256',jsonencode(ledger)));
  out=struct('summary',summary,'trial_values',trials,'trial_parameters',parameters,'trial_status',statuses,'trial_messages',{messages},'trial_columns',{{'parameter_value','weighted_sse','likelihood_ratio','direction'}},'status_codes',struct('converged',1,'solver_failure',2,'baseline_improved',3));
endfunction
function out=make_endpoint(status,value,searched,ratio,inside,outside,message)
  out=struct('status',status,'value',value,'searched_value',searched,'likelihood_ratio',ratio,'bracket_inside',inside,'bracket_outside',outside,'message',message);
endfunction
function value=field(s,key,fallback),if(isfield(s,key)),value=s.(key);else value=fallback;endif;endfunction
function scalar(value),if(!isnumeric(value)||!isreal(value)||!isscalar(value)||!isfinite(value)),error('GXTXT:Numeric:Profile','Expected finite real scalar');endif;endfunction
function value=integer(value,lo,hi),scalar(value);if(value!=fix(value)||value<lo||value>hi),error('GXTXT:Numeric:Profile','Invalid bounded integer');endif;endfunction
