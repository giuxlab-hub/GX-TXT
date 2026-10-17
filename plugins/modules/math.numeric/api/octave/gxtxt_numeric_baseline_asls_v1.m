% SPDX-License-Identifier: GPL-3.0-or-later
% Numeric owns the estimator. Call through NUMERIC_API_v1/baseline.
function out=gxtxt_numeric_baseline_asls_v1(x,y,opts)
  n=numel(y);
  if(n<3||n>2000000),error('GXTXT:Numeric:Baseline','AsLS requires 3..2000000 selected observations');endif
  lambda=number(opts,'lambda',1e5);p=number(opts,'p',0.01);
  limit=number(opts,'max_iterations',50);tolerance=number(opts,'tolerance',1e-6);
  if(lambda<=0||lambda>1e16||p<=0||p>=1||min(p,1-p)<1e-8||limit<1||limit>500||limit!=fix(limit)||tolerance<0||tolerance>=1)
    error('GXTXT:Numeric:Baseline','AsLS requires 0 < lambda <= 1e16, 1e-8 <= p <= 1-1e-8, 1..500 iterations and 0 <= tolerance < 1');
  endif
  policy='uniform_x';if(isfield(opts,'grid_policy')),policy=opts.grid_policy;endif
  if(!ischar(policy)||!any(strcmp(policy,{'uniform_x','sample_index'}))),error('GXTXT:Numeric:Baseline','grid_policy must be uniform_x or sample_index');endif
  dx=diff(x);
  if(any(!isfinite(dx))||!(all(dx>0)||all(dx<0))),error('GXTXT:Numeric:Baseline','AsLS requires strictly monotone unique X; data are never silently sorted or averaged');endif
  step=(x(end)-x(1))/(n-1);
  grid_tolerance=max(1e-8*abs(step),min(64*eps(max(abs(x))),1e-4*abs(step)));
  uniform=isfinite(step)&&max(abs(dx-step))<=grid_tolerance;
  if(strcmp(policy,'uniform_x')&&!uniform),error('GXTXT:Numeric:Baseline','AsLS requires uniform X spacing; choose sample_index explicitly to penalize consecutive selected rows on an irregular grid');endif
  % Remove an affine null-space component before the sparse augmented solve.
  % No normal equations: the compiled sparse QR backend avoids squaring the
  % condition number of the weighted difference system.
  scale=max(abs(y));if(scale==0),scale=1;endif
  scaled=y/scale;trend=scaled(1)+(scaled(end)-scaled(1))*((0:n-1)'/(n-1));target=scaled-trend;
  ii=(1:n-2)';D=sparse([ii;ii;ii],[ii;ii+1;ii+2],[ones(n-2,1);-2*ones(n-2,1);ones(n-2,1)],n-2,n);
  penalty=sqrt(lambda)*D;weights=ones(n,1);converged=false;history=zeros(limit,1);
  for iteration=1:limit
    root=sqrt(weights);
    z=[spdiags(root,0,n,n);penalty]\[root.*target;zeros(n-2,1)];
    if(any(!isfinite(z))),error('GXTXT:Numeric:Baseline','AsLS sparse solve returned nonfinite values');endif
    updated=(1-p)*ones(n,1);updated(target>z)=p;
    change=norm(updated-weights)/norm(weights);history(iteration)=change;
    if(change<=tolerance),converged=true;break;endif
    if(iteration<limit),weights=updated;endif
  endfor
  baseline=(trend+z)*scale;
  if(any(!isfinite(baseline))),error('GXTXT:Numeric:Baseline','AsLS baseline exceeds finite response range');endif
  out=struct('baseline',baseline,'weights',weights,'iterations',iteration,'converged',converged, ...
    'relative_weight_change',change,'convergence_history',history(1:iteration), ...
    'lambda',lambda,'p',p,'max_iterations',limit,'tolerance',tolerance, ...
    'difference_order',2,'grid_policy',policy,'grid_uniform',uniform,'x_step',step,'grid_tolerance',grid_tolerance, ...
    'solver','compiled_sparse_augmented_qr','weight_semantics','asymmetric_algorithm_weights_not_measurement_precision', ...
    'uncertainty_policy','baseline_treated_as_fixed_no_baseline_estimation_uncertainty');
endfunction
function value=number(opts,key,fallback)
  value=fallback;if(isfield(opts,key)),value=opts.(key);endif
  if(!isnumeric(value)||!isreal(value)||!isscalar(value)||!isfinite(value)),error('GXTXT:Numeric:Baseline','AsLS %s must be a finite real scalar',key);endif
  value=double(value);
endfunction
