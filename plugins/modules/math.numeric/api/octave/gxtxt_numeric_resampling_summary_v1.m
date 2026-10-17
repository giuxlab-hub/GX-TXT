function out=gxtxt_numeric_resampling_summary_v1(distribution,observed,opts)
% Summarize an already generated bootstrap/permutation distribution once.
% Public NUMERIC_API_v1 owns estimates; CORE owns their interpretation.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<3),opts=struct();endif
  if(!isstruct(opts)||!isscalar(opts)),error('GXTXT:Numeric','Resampling options must be a scalar struct');endif
  if(!isnumeric(distribution)||!isreal(distribution)||!isvector(distribution)||isempty(distribution)||any(!isfinite(distribution(:))))
    error('GXTXT:Numeric','Resampling distribution must be a nonempty finite real vector');
  endif
  if(!isnumeric(observed)||!isscalar(observed)||!isreal(observed)||!isfinite(observed)),error('GXTXT:Numeric','Observed resampling statistic must be finite and scalar');endif
  distribution=double(distribution(:));reps=numel(distribution);
  if(reps>1000000),error('GXTXT:Numeric','Resampling summary exceeds one million replicates');endif
  method=field(opts,'method','bootstrap');alternative=field(opts,'alternative','two_sided');confidence=field(opts,'confidence',.95);
  if(!ischar(method)||!any(strcmp(method,{'bootstrap','permutation_independent','permutation_paired'}))),error('GXTXT:Numeric','Unknown resampling method');endif
  if(!ischar(alternative)||!any(strcmp(alternative,{'two_sided','greater','less'}))),error('GXTXT:Numeric','Unknown permutation alternative');endif
  if(!isnumeric(confidence)||!isreal(confidence)||!isscalar(confidence)||!isfinite(confidence)||confidence<=0||confidence>=1),error('GXTXT:Numeric','Resampling confidence must be in (0,1)');endif
  out=struct('method',method,'replicates',reps,'estimate',observed,'confidence',confidence,'alternative',alternative, ...
    'ci_lower',NaN,'ci_upper',NaN,'p_value',NaN,'extreme_count',0,'bootstrap_standard_error',NaN,'distribution_variance',NaN, ...
    'inference','','quantile_definition','','tail_tolerance',NaN);
  for name={'n_x','n_y'}
    if(isfield(opts,name{1}))
      n=opts.(name{1});if(!isnumeric(n)||!isreal(n)||!isscalar(n)||!isfinite(n)||n<0||n!=fix(n)),error('GXTXT:Numeric','Resampling source counts must be nonnegative integers');endif
      out.(name{1})=n;
    endif
  endfor
  if(strcmp(method,'bootstrap'))
    q=gxtxt_numeric_v1('quantiles',distribution,[(1-confidence)/2;(1+confidence)/2]);
    out.ci_lower=q.quantiles(1);out.ci_upper=q.quantiles(2);out.alternative='two_sided';
    out.quantile_definition=q.definition;out.inference='percentile_confidence_interval';
    if(reps>1),out.distribution_variance=var(distribution,0);out.bootstrap_standard_error=sqrt(out.distribution_variance);endif
  else
    tolerance=32*eps(max(1,abs(observed)));out.tail_tolerance=tolerance;
    if(strcmp(alternative,'greater')),count=sum(distribution>=observed-tolerance);
    elseif(strcmp(alternative,'less')),count=sum(distribution<=observed+tolerance);
    else count=sum(abs(distribution)>=abs(observed)-tolerance);endif
    out.extreme_count=count;out.p_value=(count+1)/(reps+1);out.inference='monte_carlo_permutation_p_plus_one';
  endif
endfunction
function value=field(s,key,fallback)
  value=fallback;if(isfield(s,key)),value=s.(key);endif
endfunction
