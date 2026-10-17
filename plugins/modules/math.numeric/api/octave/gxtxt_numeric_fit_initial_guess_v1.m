% Bounded model-aware initialization; auxiliary LS stays with the Numeric owner.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_fit_initial_guess_v1(kind,X,Y,options)
  if(!ischar(kind)||isempty(regexp(kind,'^[a-z][a-z0-9_]{0,63}$','once'))),fail('Model kind must be a bounded identifier');endif
  if(!isstruct(options)||numel(options)!=1||!isempty(setdiff(fieldnames(options),{'degree','initial_parameters','lower_bounds','upper_bounds','fixed_mask'}))),fail('Unknown initialization option');endif
  if(!isfloat(X)||!isfloat(Y)||!isreal(X)||!isreal(Y)||!isvector(X)||!isvector(Y)||numel(X)!=numel(Y)||numel(X)<2||numel(X)>1000000||any(!isfinite(X(:)))||any(!isfinite(Y(:))))
    fail('Initialization needs two equal finite real floating vectors, 2..1000000 observations; select nonfinite handling explicitly upstream');
  endif
  X=double(X(:));Y=double(Y(:));n=numel(X);
  out=struct('schema','gxtxt.fit_initial_guess.v1','status','unavailable','model_kind',kind,...
    'purpose','initialization_only','nonlinear_optimization',false,'observation_count',n,...
    'nonfinite_policy','error','source_mutation',false,'auxiliary_linear_solves',0,...
    'method','','reason','','parameter_ids',{{}},'parameters',[],'model',struct(),...
    'lower_bounds',[],'upper_bounds',[],'fixed_mask',[],'clipped_mask',[]);
  if(!any(strcmp(kind,{'linear','polynomial_fit','exponential','power_law','gaussian'})))
    out.reason='No automatic initialization rule is registered for this model. Use explicit declared initial parameters and evaluate them before fitting.';return;
  endif
  degree=1;
  if(strcmp(kind,'polynomial_fit'))
    if(!isfield(options,'degree')),fail('Polynomial initialization requires explicit degree');endif
    degree=options.degree;if(!isnumeric(degree)||!isreal(degree)||!isscalar(degree)||!isfinite(degree)||degree!=fix(degree)||degree<1||degree>12),fail('Polynomial degree must be an integer from 1 to 12');endif
  elseif(isfield(options,'degree')),fail('Degree applies only to polynomial_fit');endif
  counts=struct('linear',2,'polynomial_fit',degree+1,'exponential',3,'power_law',2,'gaussian',4);p=counts.(kind);
  [lower,upper,fixed,current]=constraints(options,p);
  out.lower_bounds=lower;out.upper_bounds=upper;out.fixed_mask=fixed;
  declared=gxtxt_numeric_fit_model_v1(struct('kind',kind),p);out.parameter_ids=declared.parameter_ids;
  if(n<p),out.reason='Fewer observations than the model parameter count; supply a scientifically justified manual model.';return;endif
  parameters=[];method='';
  try
  if(all(fixed))
    parameters=current;method='retained_fixed_parameters';
  else
    xmin=min(X);xmax=max(X);span=xmax-xmin;
    if(!isfinite(span)||span<=0),out.reason='Initialization requires a finite nonzero predictor span.';return;endif
    if(strcmp(kind,'linear'))
      fit=gxtxt_numeric_v1('linear_regression',X,Y);out.auxiliary_linear_solves=1;
      if(fit.rank<p),out.reason='The initialization design is rank deficient.';return;endif
      parameters=fit.coefficients(:);method='existing_linear_least_squares';
    elseif(strcmp(kind,'polynomial_fit'))
      fit=gxtxt_numeric_v1('polynomial_fit',X,Y,degree);out.auxiliary_linear_solves=1;
      if(fit.rank<p),out.reason='The initialization design is rank deficient.';return;endif
      parameters=fit.coefficients(:);method='existing_scaled_polynomial_least_squares';
    elseif(strcmp(kind,'power_law'))
      if(any(X<=0)||any(Y==0)||!(all(Y>0)||all(Y<0))),out.reason='Log-linear power initialization needs strictly positive predictors and a nonzero response of one sign. The final response fit retains its original scale.';return;endif
      fit=gxtxt_numeric_v1('linear_regression',log(X),log(abs(Y)));out.auxiliary_linear_solves=1;
      if(fit.rank<2),out.reason='The logarithmic initialization design is rank deficient.';return;endif
      parameters=[sign(Y(1))*exp(fit.intercept);fit.slope];method='signed_log_linear_start_only';
    elseif(strcmp(kind,'gaussian'))
      [sorted,order]=sort(X);edge=max(1,floor(n/10));baseline=median(Y(order([1:edge,n-edge+1:n])));
      residual=Y-baseline;[height,index]=max(abs(residual));direction=sign(residual(index));weight=max(direction*residual,0);
      if(height<=0||!isfinite(height)),out.reason='A constant response has no identifiable Gaussian peak initializer.';return;endif
      % Scale both axes before the bounded moment heuristic to avoid overflow.
      weight=weight/height;z=(X-xmin)/span;total=sum(weight);center=sum(weight.*z)/total;
      width=sqrt(sum(weight.*(z-center).^2)/total)*span;
      parameters=[residual(index);xmin+center*span;width;baseline];method='edge_median_and_signed_peak_moments';
    elseif(strcmp(kind,'exponential'))
      ymin=min(Y);ymax=max(Y);yscale=max(abs(Y));yrange=ymax-ymin;
      if(!isfinite(yrange)||yrange<=0||yscale==0),out.reason='A constant or unrepresentable response span has no identifiable exponential initializer.';return;endif
      offsets=[0,ymin-yrange*[.01,.1,1],ymax+yrange*[.01,.1,1]];
      if(!isempty(current)),offsets=[offsets,current(3)];endif
      offsets=unique(offsets(isfinite(offsets)));best=Inf;
      for c=offsets
        shifted=Y-c;if(any(!isfinite(shifted))||any(shifted==0)||!(all(shifted>0)||all(shifted<0))),continue;endif
        fit=gxtxt_numeric_v1('linear_regression',X,log(abs(shifted)));out.auxiliary_linear_solves+=1;
        trial=[sign(shifted(1))*exp(fit.intercept);fit.slope;c];
        if(fit.rank<2||any(!isfinite(trial))),continue;endif
        candidate=declared;candidate.parameters=trial;
        try
          predicted=gxtxt_numeric_v1('nonlinear_evaluate',candidate,X).predicted;
          if(any(!isfinite(predicted))),continue;endif
          score=norm(predicted/yscale-Y/yscale);
          if(isfinite(score)&&score<best),best=score;parameters=trial;endif
        catch
          % A rejected expression domain is not a successful candidate.
        end_try_catch
      endfor
      method='bounded_offset_candidates_and_log_linear_starts';
      if(isempty(parameters)),out.reason='No finite exponential initializer could be evaluated on the supplied predictors.';return;endif
    endif
  endif
  catch err
    out.reason=['Auxiliary initialization unavailable: ' err.message];return;
  end_try_catch
  if(any(!isfinite(parameters))||numel(parameters)!=p),out.reason='The initial parameter values are outside the representable finite range.';return;endif
  proposed=parameters;parameters=max(lower,min(upper,parameters));parameters(logical(fixed))=current(logical(fixed));
  declared.parameters=parameters;
  try
    evaluation=gxtxt_numeric_v1('nonlinear_evaluate',declared,X);
    if(any(!isfinite(evaluation.predicted(:)))),error('Nonfinite predicted values');endif
  catch err
    out.reason=['Constrained initial parameters cannot be evaluated: ' err.message];return;
  end_try_catch
  out.status='proposed';out.parameters=parameters;out.model=declared;out.method=method;
  out.clipped_mask=double(parameters!=proposed & !logical(fixed));
  out.reason='Initial suggestion only. Review physical units, bounds and fixed values; run the existing fit and inspect convergence/inference separately.';
endfunction
function [lower,upper,fixed,current]=constraints(options,p)
  lower=vector(options,'lower_bounds',-Inf(p,1),p,true);upper=vector(options,'upper_bounds',Inf(p,1),p,true);
  fixed=vector(options,'fixed_mask',zeros(p,1),p,false);current=[];
  if(any(lower>upper)||any(lower==Inf)||any(upper==-Inf)||any(!ismember(fixed,[0,1]))),fail('Invalid initialization bounds or fixed mask');endif
  if(isfield(options,'initial_parameters')),current=vector(options,'initial_parameters',[],p,false);endif
  equal=lower==upper;fixed(equal)=1;
  if(isempty(current))
    if(any(logical(fixed)&!equal)),fail('Fixed initialization parameters need explicit current values');endif
    current=zeros(p,1);current(equal)=lower(equal);
  endif
  if(any(current(logical(fixed))<lower(logical(fixed)))||any(current(logical(fixed))>upper(logical(fixed)))),fail('Fixed initial values violate their bounds');endif
endfunction
function value=vector(options,name,fallback,p,infinite)
  value=fallback;if(isfield(options,name)),value=options.(name);endif
  if(!(isnumeric(value)||islogical(value))||!isreal(value)||!isvector(value)||numel(value)!=p||any(isnan(value(:)))||(!infinite&&any(!isfinite(value(:))))),fail(['Invalid initialization vector: ' name]);endif
  value=double(value(:));
endfunction
function fail(message),error('GXTXT:Numeric:InitialGuess','%s',message);endfunction
