% Shared Numeric likelihood computation from a bounded public CORE plan.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_fit_information_criteria_v1(plan)
  required={'api_id','api_version','status','n','free_parameter_count','weighted_sse','log_weight_sum','scale_model'};
  if(!isstruct(plan)||!isscalar(plan)||!all(isfield(plan,required))||...
      !strcmp(plan.api_id,'STATISTICAL_MODEL_SELECTION_PLAN_v1')||!isnumeric(plan.api_version)||!isscalar(plan.api_version)||plan.api_version!=1||!strcmp(plan.status,'value'))
    error('GXTXT:Numeric:ModelSelection','A valid public CORE model-selection plan is required');
  endif
  n=plan.n;p=plan.free_parameter_count;sse=plan.weighted_sse;lw=plan.log_weight_sum;
  if(!isscalar(n)||!isreal(n)||!isfinite(n)||n<1||n!=fix(n)||...
      !isscalar(p)||!isreal(p)||!isfinite(p)||p<0||p!=fix(p)||p>=n||...
      !isscalar(sse)||!isreal(sse)||!isfinite(sse)||sse<0||!isscalar(lw)||!isreal(lw)||!isfinite(lw)||...
      !any(strcmp(plan.scale_model,{'estimated','known'})))
    error('GXTXT:Numeric:ModelSelection','Invalid likelihood counts, SSE or normalization');
  endif
  estimated=strcmp(plan.scale_model,'estimated');k=p+estimated;variance_mle=NaN;aicc=NaN;
  if(estimated)
    if(sse==0),error('GXTXT:Numeric:ModelSelection','Estimated Gaussian scale is zero; finite maximized log likelihood is undefined');endif
    variance_mle=sse/n;
    minus_twice_log_likelihood=n*(log(2*pi)+1+log(sse)-log(n))-lw;
  else
    minus_twice_log_likelihood=n*log(2*pi)-lw+sse;
  endif
  log_likelihood=-.5*minus_twice_log_likelihood;
  aic=minus_twice_log_likelihood+2*k;bic=minus_twice_log_likelihood+k*log(n);
  aicc_computed=estimated&&(n>k+1);
  if(aicc_computed),aicc=aic+2*k*(k+1)/(n-k-1);endif
  if(any(!isfinite([log_likelihood,aic,bic]))||(aicc_computed&&!isfinite(aicc)))
    error('GXTXT:Numeric:ModelSelection','Information criteria exceed binary64 range');
  endif
  out=struct('numeric_api','NUMERIC_API_v1','operation','fit_information_criteria','plan',plan,...
    'n',n,'free_parameter_count',p,'likelihood_parameter_count',k,'log_likelihood',log_likelihood,...
    'aic',aic,'aicc',aicc,'bic',bic,'aicc_computed',logical(aicc_computed),'variance_mle',variance_mle);
endfunction
