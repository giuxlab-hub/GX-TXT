% SPDX-License-Identifier: GPL-3.0-or-later
% Captured SSE only: no fitting, residual reduction or private applicability.
function out=gxtxt_numeric_nested_f_v1(plan)
  required={'api_id','api_version','status','method','n','reduced_p','full_p','reduced_sse','full_sse','numerator_df','denominator_df'};
  if(!isstruct(plan)||!isscalar(plan)||!all(isfield(plan,required))||!strcmp(plan.api_id,'STATISTICAL_NESTED_F_PLAN_v1')||plan.api_version!=1||!strcmp(plan.status,'value')||!strcmp(plan.method,'complete_polynomial_spaces'))
    error('GXTXT:Numeric:NestedF','A valid public CORE nested-F plan is required');
  endif
  keys={'n','reduced_p','full_p','reduced_sse','full_sse','numerator_df','denominator_df'};
  for k=1:numel(keys)
    v=plan.(keys{k});if(!isnumeric(v)||!isreal(v)||!isscalar(v)||!isfinite(v)||v<0),error('GXTXT:Numeric:NestedF','Invalid captured nested-F fact');endif
  endfor
  n=plan.n;pr=plan.reduced_p;pf=plan.full_p;a=plan.numerator_df;b=plan.denominator_df;
  if(n!=fix(n)||pr!=fix(pr)||pf!=fix(pf)||pr<1||pf<=pr||pf>=n||n>flintmax()||a!=pf-pr||b!=n-pf),error('GXTXT:Numeric:NestedF','Inconsistent nested-F counts');endif
  sr=plan.reduced_sse;sf=plan.full_sse;delta=sr-sf;clamped=false;status='value';reason='';F=NaN;p=NaN;
  if(sf==0)
    status='undefined';reason='Full-model residual scale is zero; the ordinary finite F reference statistic is undefined';
  elseif(delta<0)
    if(-delta<=64*eps(max(sr,sf))),delta=0;clamped=true;
    else status='undefined';reason='Full-model SSE exceeds reduced-model SSE beyond binary64 roundoff; inspect fits and conditioning';endif
  endif
  if(strcmp(status,'value'))
    if(delta==0),F=0;p=1;
    else
      F=exp(log(delta)-log(sf)+log(b)-log(a));
      if(!isfinite(F)),status='undefined';reason='F statistic exceeds binary64 range';F=NaN;
      elseif(F>1),tail=gxtxt_numeric_v1('f_cdf',1/F,b,a);p=tail.values;
      else tail=gxtxt_numeric_v1('f_cdf',F,a,b);p=1-tail.values;
      endif
    endif
  endif
  out=struct('numeric_api','NUMERIC_API_v1','operation','nested_f_test','plan',plan,'status',status,'reason',reason,...
    'f_statistic',F,'p_value',p,'numerator_df',a,'denominator_df',b,'sse_reduction',delta,'sse_roundoff_clamped',logical(clamped));
endfunction
