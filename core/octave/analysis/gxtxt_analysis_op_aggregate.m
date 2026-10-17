% SPDX-License-Identifier: GPL-3.0-or-later
% Row-preserving aggregate; Numeric owns facts and CORE owns their availability.
function [out,details] = gxtxt_analysis_op_aggregate(value,method,group,context)
  if(nargin<3),group=[];endif;if(nargin<4),context=struct();endif
  method=lower(strtrim(method));alias=method;
  if(strcmp(method,'std')),alias='std_sample';elseif(strcmp(method,'count')),alias='n';endif
  if(!any(strcmp(method,{'mean','median','min','max','std','sum','count'}))),error('GXTXT:AnalysisAggregate','Unknown aggregate method: %s',method);endif
  lifetime=gxtxt_statistics_scope_v1();
  [groups,indices,kind]=gxtxt_analysis_group_index(group,numel(value));out=NaN(size(value));
  details=struct('status',{repmat({'unavailable'},size(value))},'reason',{repmat({'missing_group'},size(value))},'statistical_results',{cell(numel(indices),1)},'unit','');
  if(strcmp(method,'count')),details.unit='1';elseif(isfield(context,'y_unit')),details.unit=context.y_unit;endif
  if(isempty(value)),details.statistical_results={};return;endif
  for k=1:numel(indices)
    idx=indices{k};raw=gxtxt_analysis_numeric_call('statistics',value(idx),struct('nonfinite','omit','empty_policy','undefined'));
    provenance=struct('analysis_operation','aggregate','aggregate_method',method,'group_kind',kind,'group_value',groups{k});
    captured=gxtxt_statistics_v1('from_numeric','math.numeric.summary','statistics',raw,context,struct(),provenance);
    fields=gxtxt_statistics_v1('numeric_fields',captured);item=fields.(alias);
    feature=gxtxt_statistics_v1('feature',captured,item.quantity);
    out(idx)=feature.value;details.status(idx)={feature.status};details.reason(idx)={feature.reason};details.unit=item.unit_text;
    details.statistical_results{k}=captured;
  endfor
endfunction
