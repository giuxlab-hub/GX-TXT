function R=gxtxt_numeric_local_cloud_fit_v1(x,y,query,options)
% Deterministic local quadratic/constant estimator for unlabelled point clouds.
% Retains the accepted nearest-neighbour/tricube estimator. Its effective
% variance denominator is a heuristic, not sampling degrees of freedom.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<4),options=struct();endif
  if(!isstruct(options)||!isscalar(options)||!isempty(fieldnames(options))),error('GXTXT:Numeric','Local cloud fit has no optional estimator overrides');endif
  for item={x,y,query}
    v=item{1};if(!isnumeric(v)||!isreal(v)||!isvector(v)||isempty(v)||any(!isfinite(v(:)))),error('GXTXT:Numeric','Local cloud inputs must be nonempty finite real vectors');endif
  endfor
  x=double(x(:));y=double(y(:));query=double(query(:));n=numel(x);
  if(numel(y)!=n),error('GXTXT:Numeric','Cloud X and Y counts must match');endif
  if(any(query<min(x))||any(query>max(x))),error('GXTXT:Numeric','Local cloud query must lie inside the source X domain');endif
  nq=numel(query);k=min(n,min(25,max(10,round(1.5*sqrt(n)))));
  R=struct('query',query,'local_mean',NaN(nq,1),'local_sigma',NaN(nq,1), ...
    'local_effective_n',NaN(nq,1),'local_dof',NaN(nq,1),'local_count',repmat(k,nq,1), ...
    'local_degree',NaN(nq,1),'quadratic_condition',NaN(nq,1), ...
    'method','nearest_tricube_quadratic_or_constant','variance_correction','kish_effective_n_minus_parameters', ...
    'insufficient_policy','undefined_without_positive_variance_denominator');
  if(n<4),return;endif
  for qi=1:nq
    x0=query(qi);[~,order]=sortrows([abs(x-x0),x,y],[1 2 3]);indices=order(1:k);
    z=x(indices)-x0;yy=y(indices);distance=max(abs(z));
    if(distance<=0),weights=ones(k,1);else,u=min(1,abs(z)/distance);weights=max((1-u.^3).^3,1e-6);endif
    design=[ones(k,1),z,z.^2];
    fit=gxtxt_numeric_v1('least_squares',design,yy,weights,struct('rank_policy','minimum_norm'));
    R.quadratic_condition(qi)=fit.condition_number;
    if(fit.rank==3&&fit.condition_number<1e6)
      predicted=fit.predicted;mu=fit.coefficients(1);parameters=3;
    else
      weighted=gxtxt_numeric_v1('weighted_statistics',yy,weights,struct());
      mu=weighted.mean;predicted=repmat(mu,k,1);parameters=1;
    endif
    sumw=sum(weights);effective=sumw^2/sum(weights.^2);denominator=effective-parameters;
    R.local_mean(qi)=mu;R.local_effective_n(qi)=effective;R.local_dof(qi)=denominator;R.local_degree(qi)=parameters-1;
    if(denominator>0)
      variance=sum(weights.*((yy-predicted).^2))/sumw*(effective/denominator);
      if(isfinite(variance)&&variance>=0),R.local_sigma(qi)=sqrt(variance);endif
    endif
  endfor
endfunction
