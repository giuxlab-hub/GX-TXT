% SPDX-License-Identifier: GPL-3.0-or-later
% Native/declared refit driver; shared sampling and summaries also serve callbacks.
function out=gxtxt_numeric_fit_bootstrap_v1(model,X,y,plan,options)
  if(nargin<5),options=struct();endif
  prepared=gxtxt_numeric_fit_bootstrap_state_v1('prepare',model,X,y,plan,options);
  model=prepared.model;if(strcmp(field(model,'kind',''),'registered_callback_evaluation')),error('GXTXT:Numeric:Bootstrap','Live callback refits require the public Script Bridge driver');endif
  p=plan.p;reps=plan.replicates;seed=plan.seed;limit=plan.max_seconds;free=plan.free_parameter_count;operation=plan.source_operation;semantics=plan.weight_semantics;
  parameters=prepared.parameters;fixed=logical(prepared.fixed_mask);policy=prepared.solver_policy;
  samples=NaN(reps,p);status=zeros(reps,1,'uint8');seeds=zeros(reps,1,'uint32');messages={};state=seed;attempted=0;clock=tic();
  for trial=1:reps
    remaining=limit-toc(clock);if(remaining<=0),break;endif
    seeds(trial)=uint32(state);attempted+=1;
    try
      draw=gxtxt_numeric_fit_bootstrap_state_v1('draw',prepared,state);state=draw.next_seed;localX=draw.predictors;localY=draw.response;localW=draw.weights;
      if(any(!isfinite(localY))),status(trial)=4;continue;endif
      remaining=limit-toc(clock);if(remaining<=0),status(trial)=7;break;endif
      localPolicy=policy;localPolicy.max_seconds=remaining;
      if(strcmp(semantics,'unweighted')),fitW=[];else fitW=localW;endif
      switch(operation)
        case 'least_squares'
          current=gxtxt_numeric_v1('least_squares',localX,localY,fitW,struct('weight_semantics',semantics_option(semantics),'rank_policy','error'));
        case 'linear_regression'
          current=gxtxt_numeric_v1('linear_regression',localX,localY,fitW,struct('intercept',p==2,'weight_semantics',semantics_option(semantics),'rank_policy','error'));
        case 'polynomial_fit'
          current=gxtxt_numeric_v1('polynomial_fit',localX,localY,p-1,fitW,struct('weight_semantics',semantics_option(semantics),'rank_policy','error'));
        case 'nonlinear_fit'
          if(!isempty(fitW)),localPolicy.weights=fitW;endif
          current=gxtxt_numeric_v1('nonlinear_fit',model,localX,localY,parameters,localPolicy);
      endswitch
      values=field(current,'coefficients',field(current,'parameters',[]));values=values(:);
      if(current.rank!=free),status(trial)=2;
      elseif(!field(current,'converged',true)),status(trial)=3;
      elseif(numel(values)!=p||any(!isfinite(values))||any(values(fixed)!=parameters(fixed))),status(trial)=4;
      else
        samples(trial,:)=values';status(trial)=1;
        if(any(field(current,'active_bounds',false(p,1))&!fixed)),status(trial)=6;endif
      endif
    catch failure
      text=lower(failure.message);
      if(!isempty(strfind(text,'rank deficient'))||!isempty(strfind(text,'zero-spread'))),status(trial)=2;else status(trial)=5;endif
      message=failure.message(1:min(512,numel(failure.message)));
      if(numel(messages)<8&&!any(strcmp(messages,message))),messages{end+1}=message;endif
    end_try_catch
  endfor
  execution=struct('attempted_count',attempted,'next_seed',state,'elapsed_seconds',toc(clock),'messages',{messages});
  out=gxtxt_numeric_fit_bootstrap_state_v1('summarize',prepared,samples,status,seeds,execution);
endfunction
function value=semantics_option(value),if(strcmp(value,'unweighted')),value='relative';endif;endfunction
function value=field(s,key,fallback),if(isfield(s,key)),value=s.(key);else value=fallback;endif;endfunction
