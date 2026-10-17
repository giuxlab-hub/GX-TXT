% Bounded strategy over the existing declared-model Ceres fit, without refitting
% the selected result or retaining every trial's observation arrays.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_multistart_v1(model,X,y,initial,opts)
  mode=field(opts,'multistart_mode','single');
  if(!any(strcmp(mode,{'explicit','uniform'}))),error('GXTXT:Numeric:Multistart','Choose single, explicit or uniform multistart mode');endif
  if(!isnumeric(initial)||!isreal(initial)),error('GXTXT:Numeric:Multistart','Initial parameters must be real numeric values');endif
  initial=double(initial(:));p=numel(initial);
  if(p<1||p>128||!isreal(initial)||any(!isfinite(initial))),error('GXTXT:Numeric:Multistart','Multistart needs one to 128 finite initial parameters');endif
  count=field(opts,'multistart_count',8);limit=field(opts,'multistart_max_seconds',60);
  if(!isnumeric(count)||!isscalar(count)||!isreal(count)||!isfinite(count)||count!=fix(count)||count<2||count>64),error('GXTXT:Numeric:Multistart','Multistart count must be an integer from 2 to 64');endif
  if(!isnumeric(limit)||!isscalar(limit)||!isreal(limit)||!isfinite(limit)||limit<=0||limit>86400),error('GXTXT:Numeric:Multistart','Multistart time limit must be in (0,86400] seconds');endif
  lb=vector(opts,'lower_bounds',p,-Inf);ub=vector(opts,'upper_bounds',p,Inf);fixed=vector(opts,'fixed_mask',p,0);
  if(any(!ismember(fixed,[0,1]))||any(isnan(lb))||any(isnan(ub))||any(lb>ub)||any(initial<lb)||any(initial>ub)),error('GXTXT:Numeric:Multistart','Invalid bounds, fixed mask or initial values');endif
  fixed=logical(fixed)|(lb==ub);starts=repmat(initial',count,1);seed=0;next_seed=0;generator='none';lo=[];hi=[];
  if(strcmp(mode,'explicit'))
    extra=field(opts,'multistart_initials',[]);
    if(!isnumeric(extra)||!isreal(extra)||!isequal(size(extra),[count-1,p])||any(!isfinite(extra(:)))),error('GXTXT:Numeric:Multistart','Explicit additional initials must be (count-1) by parameter-count finite values');endif
    starts(2:end,:)=double(extra);
  else
    seed=field(opts,'multistart_seed',1);
    if(!isnumeric(seed)||!isscalar(seed)||!isreal(seed)||!isfinite(seed)||seed!=fix(seed)||seed<1||seed>2147483646),error('GXTXT:Numeric:Multistart','Seed must be an integer from 1 to 2147483646');endif
    lo=vector(opts,'multistart_lower',p,NaN);hi=vector(opts,'multistart_upper',p,NaN);
    if(any(!isfinite(lo))||any(!isfinite(hi))||any(lo>hi)||any(lo<lb)||any(hi>ub)),error('GXTXT:Numeric:Multistart','Uniform start ranges must be finite, ordered and inside solver bounds');endif
    draws=gxtxt_numeric_v1('resample_indices',2147483646,p,count-1,seed);
    % With this population, the public generator's integer index is its exact
    % Park-Miller state. Convex interpolation avoids overflow in (upper-lower).
    u=draws.indices/2147483647;
    starts(2:end,:)=(1-u).*lo'+u.*hi';
    starts(:,fixed)=repmat(initial(fixed)',count,1);
    next_seed=draws.next_seed;generator=draws.generator;
  endif
  if(any(any(starts<lb'|starts>ub'))||any(any(starts(:,fixed)!=repmat(initial(fixed)',count,1)))),error('GXTXT:Numeric:Multistart','Every start must respect bounds and preserve fixed parameters');endif
  local=opts;names=fieldnames(local);
  for k=1:numel(names),if(strncmp(names{k},'multistart_',11)),local=rmfield(local,names{k});endif;endfor
  if(isfield(local,'threads')&&(!isnumeric(local.threads)||!isscalar(local.threads)||local.threads!=1)),error('GXTXT:Numeric:Multistart','Reproducible sequential multistart requires threads=1');endif
  local.threads=1;
  % Keep one common scaling policy across trials. Explicit caller scales win.
  if(!isfield(local,'parameter_scales')),local.parameter_scales=abs(initial);local.parameter_scales(local.parameter_scales==0)=1;endif
  receipt=struct('schema','gxtxt.numeric_multistart_receipt.v1','mode',mode,'requested_count',count, ...
    'seed',seed,'next_seed',next_seed,'generator',generator,'strategy_version',1, ...
    'initials',starts,'range_lower',lo,'range_upper',hi,'max_seconds',limit, ...
    'execution_policy','sequential_one_thread_per_trial','cancellation_policy','worker_cancellation_discards_incomplete_result', ...
    'selection_policy','lowest_finite_objective_among_converged_else_provisional;first_index_breaks_exact_ties', ...
    'trials',{{}},'selected_index',0,'converged_count',0,'attempted_count',0,'completed_count',0,'error_count',0,'elapsed_seconds',0);
  clock=tic();bestObjective=Inf;bestConverged=false;haveResult=false;
  for index=1:count
    remaining=limit-toc(clock);
    trial=struct('index',index,'initial_parameters',starts(index,:)', 'status','not_run_time_limit','message','Overall multistart time limit reached');
    if(remaining>0)
      receipt.attempted_count+=1;local.max_seconds=min(field(opts,'max_seconds',3600),remaining);
      try
        current=gxtxt_numeric_declared_fit_v1(model,X,y,starts(index,:)',local);
        trial.status='completed';trial.message='';trial.parameters=current.parameters;trial.solver_receipt=current.solver_receipt;
        receipt.completed_count+=1;converged=logical(current.converged);objective=current.solver_objective;
        receipt.converged_count+=double(converged);
        if(isfinite(objective)&&objective>=0&&(!haveResult||(converged&&!bestConverged)||(converged==bestConverged&&objective<bestObjective)))
          out=current;haveResult=true;bestObjective=objective;bestConverged=converged;receipt.selected_index=index;
        endif
      catch failure
        trial.status='error';trial.message=failure.message(1:min(2048,numel(failure.message)));receipt.error_count+=1;
      end_try_catch
    endif
    receipt.trials{index}=trial;
  endfor
  receipt.elapsed_seconds=toc(clock);
  if(!haveResult)
    error('GXTXT:Numeric:Multistart','No finite multistart result: %s',jsonencode(receipt));
  endif
  out.solver_receipt.multistart=receipt;
  out.model.multistart=receipt;
endfunction
function value=field(s,key,fallback),if(isfield(s,key)),value=s.(key);else value=fallback;endif;endfunction
function value=vector(s,key,n,fallback)
  value=field(s,key,repmat(fallback,n,1));
  if((!isnumeric(value)&&!islogical(value))||!isreal(value)||numel(value)!=n),error('GXTXT:Numeric:Multistart','Invalid %s vector',key);endif
  value=double(value(:));
endfunction
