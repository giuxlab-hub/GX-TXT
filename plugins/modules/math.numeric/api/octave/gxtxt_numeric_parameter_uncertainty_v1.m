function out=gxtxt_numeric_parameter_uncertainty_v1(plan)
% Bounded covariance normalization and marginal intervals, without refitting.
% Scientific applicability and labels come from the public CORE plan.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(!isstruct(plan)||!isscalar(plan)||!isfield(plan,'api_id')|| ...
     !strcmp(plan.api_id,'STATISTICAL_PARAMETER_INFERENCE_PLAN_v1')||plan.api_version!=1||!strcmp(plan.status,'value'))
    error('GXTXT:Numeric','parameter_uncertainty requires an eligible public CORE inference plan');
  endif
  p=plan.source_parameters(:);C=plan.source_covariance;n=numel(p);
  if(!isnumeric(p)||!isreal(p)||any(!isfinite(p))||n<1||n>256|| ...
     !isnumeric(C)||!isreal(C)||!isequal(size(C),[n n])||any(!isfinite(C(:)))|| ...
     !iscellstr(plan.parameter_ids)||numel(plan.parameter_ids)!=n||numel(unique(plan.parameter_ids))!=n|| ...
     !iscellstr(plan.parameter_units)||numel(plan.parameter_units)!=n)
    error('GXTXT:Numeric','Invalid bounded parameter covariance or identities');
  endif
  variance=diag(C);
  if(any(variance<=0)),error('GXTXT:Numeric','Parameter correlation requires strictly positive variances');endif
  se=sqrt(variance);R=bsxfun(@rdivide,bsxfun(@rdivide,C,se),se');
  if(norm(R-R','inf')>1e-10||any(abs(R(:))>1+1e-10)||min(eig((R+R')/2)) < -1e-10)
    error('GXTXT:Numeric','Parameter covariance is not a symmetric positive semidefinite matrix');
  endif
  % Bound only floating-point rounding around the exact correlation limits.
  R=max(-1,min(1,(R+R')/2));R(1:n+1:end)=1;
  out=struct('numeric_api','NUMERIC_API_v1','operation','parameter_uncertainty','plan',plan,'correlation',R);
  if(!strcmp(plan.interval_status,'value'))
    if(!strcmp(plan.distribution,'none')),error('GXTXT:Numeric','Ineligible interval plan declares a distribution');endif
    return;
  endif
  confidence=plan.confidence;
  if(!isnumeric(confidence)||!isscalar(confidence)||!isfinite(confidence)||confidence<=0||confidence>=1)
    error('GXTXT:Numeric','Invalid interval confidence');
  endif
  switch(plan.distribution)
    case 'normal'
      critical=-sqrt(2)*erfcinv(1+confidence);
    case 'student_t'
      critical=gxtxt_numeric_v1('student_t_quantile',(1+confidence)/2,plan.degrees_of_freedom).values;
    otherwise,error('GXTXT:Numeric','Unsupported CORE interval distribution');
  endswitch
  out.lower=p-critical*se;out.upper=p+critical*se;out.critical_value=critical;
  if(!isfinite(critical)||any(!isfinite(out.lower))||any(!isfinite(out.upper)))
    error('GXTXT:Numeric','Parameter interval overflows the finite numeric range');
  endif
endfunction
