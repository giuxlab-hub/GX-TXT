% SPDX-License-Identifier: GPL-3.0-or-later
function [out,details] = gxtxt_analysis_op_normalize(value,method,context)
  if(nargin<3),context=struct();endif;method=lower(strtrim(method));
  if(!any(strcmp(method,{'maxabs','max','rms','minmax','zscore'}))),error('GXTXT:AnalysisNormalize','Unknown normalization method: %s',method);endif
  if(isempty(value)),out=value;details=struct('statistical_results',{{}},'unit','1','status',{{}},'reason',{{}});return;endif
  lifetime=gxtxt_statistics_scope_v1();
  raw=gxtxt_analysis_numeric_call('statistics',value(:),struct('nonfinite','omit','empty_policy','undefined'));
  captured=gxtxt_statistics_v1('from_numeric','math.numeric.summary','statistics',raw,context,struct(),struct('analysis_operation','normalize','normalization_method',method,'sample_role','input_before_normalization'));
  facts=gxtxt_statistics_values_v1(captured);
  details=struct('statistical_results',{{captured}},'unit','1');finite=isfinite(value);out=value;
  if(!any(finite(:))),details=availability(details,value,out);return;endif
  switch method
    case 'maxabs',scale=facts.absolute_maximum;if(scale==0),scale=1;endif;out=value./scale;
    case 'max',scale=facts.maximum;if(scale==0),scale=1;endif;out=value./scale;
    case 'rms',scale=facts.root_mean_square;if(scale==0),scale=1;endif;out=value./scale;
    case 'minmax'
      lo=facts.minimum;hi=facts.maximum;
      if(hi==lo),out(finite)=0;else out=(value-lo)./(hi-lo);endif
    case 'zscore'
      values=value(finite);location=facts.mean;scale=facts.standard_deviation;
      % Constant-input normalization is a transformation convention, not a
      % declaration that a singleton has a measured zero sample spread.
      if(all(values==values(1))),scale=1;endif
      out=(value-location)./scale;
  endswitch
  details=availability(details,value,out);
endfunction
function details=availability(details,input,output)
  details.status=repmat({'valid'},size(output));details.reason=repmat({''},size(output));
  bad=!isfinite(output);details.status(bad)={'unavailable'};details.reason(bad)={'normalization_statistic_unavailable'};
  missing=!isfinite(input);details.status(missing)={'unavailable'};details.reason(missing)={'nonfinite_source'};
endfunction
