% Full observation-covariance linear regression. PSD null modes are exact
% constraints, never discarded residuals or silently regularized directions.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_gls_v1(A,y,C,options)
  if(nargin<4),options=struct();endif
  if(!isstruct(options)||!isscalar(options)||!isempty(setdiff(fieldnames(options),{'covariance_semantics','singular_policy','eigen_relative_tolerance','symmetry_relative_tolerance','constraint_relative_tolerance','max_lag'})))
    fail('Unknown GLS option');
  endif
  A=finite_real(A,'design');y=finite_real(y,'response');C=finite_real(C,'observation covariance');
  if(!isvector(y)),fail('Response must be one explicit vector');endif
  n=rows(A);p=columns(A);y=y(:);
  if(n<1||n>2048||p<1||p>64||numel(y)!=n||!isequal(size(C),[n,n])),fail('GLS requires1..2048 rows,1..64 design columns and a matching square covariance');endif
  semantics=option(options,'covariance_semantics','absolute');policy=option(options,'singular_policy','reject');
  if(!ischar(semantics)||!any(strcmp(semantics,{'absolute','relative_scale'}))||!ischar(policy)||!any(strcmp(policy,{'reject','exact_constraints'}))),fail('Declare absolute or relative_scale covariance and reject or exact_constraints singular policy');endif
  ertol=scalar_option(options,'eigen_relative_tolerance',64*eps*n,0,1e-6);
  srtol=scalar_option(options,'symmetry_relative_tolerance',64*eps*n,0,1e-6);
  crtol=scalar_option(options,'constraint_relative_tolerance',512*eps*max(n,p),0,1e-6);
  lag=scalar_option(options,'max_lag',min(10,max(1,n-1)),1,64);if(lag!=fix(lag)),fail('max_lag must be an integer');endif
  original_hash=digest(C);cscale=max(abs(C(:)));asymmetry=max(abs((C-C.')(:)));
  if(asymmetry>srtol*cscale),fail('Observation covariance is not symmetric within the declared relative tolerance');endif
  C=C/2+C.'/2;[U,D]=eig(C);lambda=diag(D);[lambda,order]=sort(lambda);U=U(:,order);
  if(any(!isfinite(lambda))||any(!isfinite(U(:)))),fail('Observation covariance eigendecomposition is not finite');endif
  cutoff=ertol*max(abs(lambda));minimum=min(lambda);
  if(minimum < -cutoff),fail('Observation covariance has a negative eigenvalue beyond the declared tolerance');endif
  positive=lambda>cutoff;r=sum(positive);null_count=n-r;
  if(null_count&&strcmp(policy,'reject')),fail('Singular covariance requires explicit exact_constraints policy');endif
  column_scale=max(abs(A),[],1);column_scale(column_scale==0)=1;B=A./column_scale;
  gamma0=zeros(p,1);Z=eye(p);constraint_rank=0;constraint_error=0;constraint_limit=0;
  if(null_count)
    E=U(:,!positive).'*B;f=U(:,!positive).'*y;
    [EU,ES,EV]=svd(E);k=min(size(ES));es=diag(ES(1:k,1:k));
    % A null eigenbasis multiplied by an exactly orthogonal design has
    % roundoff-sized entries. Rank must be relative to the original scaled
    % design, not to those spurious near-zero entries alone.
    etol=crtol*max(norm(B,2),realmin);
    constraint_rank=sum(es>etol);
    if(constraint_rank),gamma0=EV(:,1:constraint_rank)*((EU(:,1:constraint_rank).'*f)./es(1:constraint_rank));endif
    Z=EV(:,constraint_rank+1:end);
    constraint_error=norm(E*gamma0-f,Inf);constraint_limit=crtol*max([norm(f,Inf),norm(E,Inf)*norm(gamma0,Inf),norm(y,Inf),realmin]);
    if(constraint_error>constraint_limit),fail('Response is inconsistent with the exact zero-variance observation constraints');endif
  endif
  if(null_count)
    W=U(:,positive).'./sqrt(lambda(positive));method='eigen_positive_modes_with_exact_null_constraints';
    WA=W*B;wy=W*y;
  else
    [L,flag]=chol(C,'lower');if(flag),fail('Positive covariance could not be factored without regularization');endif
    WA=L\B;wy=L\y;method='lower_cholesky_in_source_order';
  endif
  free=columns(Z);dof=r-free;
  if(dof<0),fail('Too few stochastic modes to identify the unconstrained parameter directions');endif
  gamma=gamma0;covariance=NaN(p,p);scale=NaN;condition=1;
  if(free)
    design=WA*Z;rhs=wy-WA*gamma0;
    solve=gxtxt_numeric_v1('least_squares',design,rhs,ones(r,1),struct('weight_semantics','inverse_variance','rank_policy','error','nonfinite','error'));
    gamma+=Z*solve.coefficients;condition=solve.scaled_condition_number;
    if(dof>0),unit_covariance=solve.covariance;
    else
      % Known covariance can identify parameters even at zero residual DOF.
      % The same factor/covariance authority supplies this saturated case.
      factor=gxtxt_numeric_jacobian_factor_v1(design,false(free,1));
      unit_covariance=gxtxt_numeric_fit_covariance_v1(factor,1);
    endif
  else,unit_covariance=zeros(0,0);endif
  coefficients=gamma./column_scale(:);predicted=A*coefficients;residual=y-predicted;
  if(any(!isfinite(coefficients))||any(!isfinite(predicted))),fail('GLS parameter/prediction overflow');endif
  if(null_count)
    final_error=norm(U(:,!positive).'*residual,Inf);
    final_limit=crtol*max([norm(y,Inf),norm(A,Inf)*norm(coefficients,Inf),realmin]);
    if(final_error>final_limit),fail('Computed coefficients violate the exact covariance null constraints');endif
    constraint_error=max(constraint_error,final_error);constraint_limit=max(constraint_limit,final_limit);
    innovations=W*residual;
  else,innovations=L\residual;endif
  objective=sum(innovations.^2);physical_sse=sum(residual.^2);
  if(!isfinite(objective)||!isfinite(physical_sse)),fail('GLS residual objective overflow');endif
  if(!free)
    covariance=zeros(p,p);scale=0;uncertainty='deterministic_constraints';
  elseif(strcmp(semantics,'absolute'))
    scale=1;uncertainty='known_covariance';
  elseif(dof>0)
    scale=objective/dof;uncertainty='estimated_scale';
  else,uncertainty='unavailable_no_residual_dof';endif
  if(free&&isfinite(scale))
    T=Z./column_scale(:);covariance=(T*unit_covariance*T.')*scale;
  endif
  variance=diag(covariance);finite_variance=isfinite(variance);variance(finite_variance)=max(variance(finite_variance),0);
  sequence=struct();if(r>=2),sequence=gxtxt_numeric_v1('residual_sequence',innovations,[],struct('ordering','input','max_lag',min(lag,r-1)));endif
  out=struct('schema','gxtxt.generalized_least_squares_numeric.v1','numeric_api','NUMERIC_API_v1','operation','generalized_least_squares',...
    'coefficients',coefficients,'covariance',covariance,'standard_errors',sqrt(variance),...
    'predicted',predicted,'residuals',residual,'whitened_residuals',innovations,'whitened_sequence',sequence,...
    'observation_count',n,'parameter_count',p,'covariance_rank',r,'covariance_nullity',null_count,...
    'exact_constraint_rank',constraint_rank,'stochastic_parameter_count',free,'dof',dof,...
    'objective',objective,'physical_sse',physical_sse,'physical_rmse',sqrt(physical_sse/n),...
    'covariance_semantics',semantics,'covariance_scale',scale,'uncertainty_status',uncertainty,...
    'singular_policy',policy,'whitening_method',method,'minimum_covariance_eigenvalue',minimum,...
    'covariance_eigenvalue_cutoff',cutoff,'eigen_relative_tolerance',ertol,'symmetry_relative_tolerance',srtol,...
    'constraint_relative_tolerance',crtol,'covariance_asymmetry',asymmetry,...
    'exact_constraint_error',constraint_error,'exact_constraint_limit',constraint_limit,...
    'scaled_design_condition',condition,'covariance_sha256',original_hash,'effective_covariance_sha256',digest(C),...
    'observation_signature',gxtxt_numeric_v1('fit_observation_signature',y,[],[],A),...
    'nonfinite_policy','error','row_policy','all_input_rows_in_original_order','regularization','none');
  out.summary=rmfield(out,{'predicted','residuals','whitened_residuals'});out.summary.schema='gxtxt.gls_numeric_summary.v1';
endfunction
function value=finite_real(value,label)
  if(!isfloat(value)||!isreal(value)||ndims(value)>2||isempty(value)||any(!isfinite(value(:)))),fail(['Finite real floating-point ' label ' is required']);endif
  value=double(value);
endfunction
function value=option(options,key,default),value=default;if(isfield(options,key)),value=options.(key);endif;endfunction
function value=scalar_option(options,key,default,lo,hi)
  value=option(options,key,default);if(!isnumeric(value)||!isreal(value)||!isscalar(value)||!isfinite(value)||value<lo||value>hi),fail(['Invalid ' key]);endif
endfunction
function text=digest(values)
  [~,~,endian]=computer();if(endian=='B'),values=swapbytes(values);endif
  text=hash('sha256',['gxtxt.gls.covariance.v1:float64:le:' char(typecast(values(:),'uint8')(:)')]);
endfunction
function fail(message),error('GXTXT:Numeric:GLS',message);endfunction
