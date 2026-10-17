% Shared Numeric inference computation; CORE Statistics owns interpretation.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_fit_diagnostics_v1(parameters,observed,predicted,J,w,options,factor)
  parameters=parameters(:);observed=observed(:);predicted=predicted(:);w=w(:);
  n=numel(observed);p=numel(parameters);
  if(n<1||p<1||rows(J)!=n||columns(J)!=p||numel(predicted)!=n||numel(w)!=n||any(!isfinite(J(:)))||any(!isfinite(predicted))||any(!isfinite(observed))||any(!isfinite(parameters))||any(!isfinite(w))||any(w<0)||sum(w)<=0)
    error('GXTXT:Numeric:Diagnostics','Inconsistent or nonfinite fit diagnostics');
  endif
  fixed=getfield_default(options,'fixed_mask',false(p,1));fixed=logical(fixed(:));
  if(numel(fixed)!=p),error('GXTXT:Numeric:Diagnostics','Fixed mask length mismatch');endif
  if(nargin<7),factor=gxtxt_numeric_jacobian_factor_v1(J,fixed);endif
  if(factor.n!=n||factor.p!=p||!isequal(factor.free,find(!fixed))),error('GXTXT:Numeric:Jacobian','Factorization dimensions or constraints changed');endif
  free=factor.free;free_count=factor.free_count;column_scale=factor.column_scale;
  s=factor.singular_values;V=factor.right_vectors;rnk=factor.rank;
  condition=factor.condition_number;scaled_condition=factor.scaled_condition_number;
  residual=observed-predicted;weighted=sqrt(w).*residual;
  odr=isfield(options,'normalized_coordinate_corrections');
  if(odr)
    corrections=options.normalized_coordinate_corrections;
    if(!isequal(size(corrections),[n,2])||any(!isfinite(corrections(:)))),error('GXTXT:Numeric:Diagnostics','Invalid normalized XY correction shape or values');endif
    weighted=hypot(corrections(:,1),corrections(:,2));
  endif
  sse=sum(weighted.^2);dof=n-rnk;
  semantics=getfield_default(options,'weight_semantics','unweighted');covariance_scale=NaN;chi2=NaN;
  covariance=NaN(p,p);standard_errors=NaN(p,1);
  infer=strcmp(getfield_default(options,'loss','linear'),'linear')&&!any(getfield_default(options,'active_bounds',false));
  if(dof>0&&rnk==free_count&&infer)
    if(strcmp(semantics,'inverse_variance')),covariance_scale=1;chi2=sse/dof;else covariance_scale=sse/dof;endif
    covariance=gxtxt_numeric_fit_covariance_v1(factor,covariance_scale);
    standard_errors=sqrt(max(diag(covariance),0));
  endif
  mu=sum(w.*observed)/sum(w);sst=sum(w.*(observed-mu).^2);r2=NaN;adjusted=NaN;
  if(sst>0&&!odr&&!getfield_default(options,'multiple_responses',false)),r2=1-sse/sst;endif
  if(dof>0&&n>1&&isfinite(r2)),adjusted=1-(1-r2)*(n-1)/dof;endif
  physical_sse=NaN;response_rmse=NaN;
  if(!odr)
    if(strcmp(semantics,'unweighted')),physical_sse=sse;else physical_sse=sum(residual.^2);endif
    response_rmse=sqrt(physical_sse/n);
  endif
  rmse=NaN;physical_rmse=NaN;if(dof>0),rmse=sqrt(sse/dof);physical_rmse=sqrt(physical_sse/dof);endif
  if(odr),physical_rmse=NaN;sst=NaN;residual=weighted;endif
  out=struct('parameters',parameters,'predicted',predicted,'residuals',residual,'weighted_residuals',weighted,...
    'objective',sse,'sse',sse,'rss',sse,'rmse',rmse,'residual_rmse',physical_rmse,'response_rmse',response_rmse,'r_squared',r2,...
    'adjusted_r_squared',adjusted,'dof',dof,'rank',rnk,'condition_number',condition,'scaled_condition_number',scaled_condition,...
    'covariance',covariance,'standard_errors',standard_errors,'jacobian',J,'weighted',!strcmp(semantics,'unweighted'),...
    'weight_semantics',semantics,'covariance_scale',covariance_scale,'reduced_chi_squared',chi2,'n',n,'p',p,...
    'free_parameter_count',free_count,'fixed_mask',fixed,'response_variance',sst/sum(w),'covariance_method','column_scaled_jacobian_qr_svd');
  if(isfield(options,'predictor_values'))
    out.observation_signature=gxtxt_numeric_fit_observations_v1(observed,w,[],options.predictor_values);
  else
    out.observation_signature=gxtxt_numeric_fit_observations_v1(observed,w);
  endif
endfunction
function value=getfield_default(s,key,fallback),if(isfield(s,key)),value=s.(key);else value=fallback;endif;endfunction
