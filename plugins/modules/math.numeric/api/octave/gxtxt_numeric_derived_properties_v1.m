% SPDX-License-Identifier: GPL-3.0-or-later
% Use the existing unit compiler, native AD and public covariance owner once.
function out=gxtxt_numeric_derived_properties_v1(plan)
  if(!isstruct(plan)||!isfield(plan,'api_id')||!strcmp(plan.api_id,'STATISTICAL_DERIVED_PROPERTIES_PLAN_v1')||plan.api_version!=1),fail('A CORE derived-properties plan is required');endif
  ids=celltext(plan.parameter_aliases);values=plan.parameter_values(:);units=celltext(plan.parameter_units);free=plan.free_indices(:);
  if(isempty(values)||numel(values)>128||numel(ids)!=numel(values)||numel(units)!=numel(values)||any(!isfinite(values))||any(free<1|free>numel(values)|free!=fix(free))||numel(unique(free))!=numel(free)),fail('Invalid captured parameter identities');endif
  definitions=items(plan.definitions);n=numel(definitions);
  if(n<1||n>32),fail('Define1..32 properties');endif
  rows=cell(1,n);J=zeros(n,numel(free));available=[];
  for i=1:n
    d=definitions{i};expression=d.expression;parameters={};used=false(1,numel(ids));
    for k=1:numel(ids)
      if(!isempty(regexp(expression,['\<' ids{k} '\>'],'once')))
        parameters{end+1}=struct('id',ids{k},'unit',units{k},'initial',values(k));used(k)=true;
      endif
    endfor
    if(!any(used)),fail('A derived property must depend on at least one captured parameter alias');endif
    constants=items(d.constants);
    for k=1:numel(constants)
      c=constants{k};parameters{end+1}=struct('id',c.id,'unit',c.unit,'initial',c.value);
    endfor
    recipe=struct('expression',expression,'predictor_ids',{{'gx_query'}},'predictor_units',{{'1'}},'response_unit',d.unit,'parameters',{parameters});
    model=gxtxt_numeric_v1('fit_formula_compose',recipe);
    row=struct('id',d.id,'value_status','value','value',NaN,'reason','','derivative_valid',true,'source_sha256',model.source_sha256,'binding_sha256',model.binding_sha256);
    try
      evaluated=gxtxt_numeric_v1('nonlinear_evaluate',model,0);
      row.value=evaluated.predicted(1);
      for j=1:numel(free)
        k=free(j);if(!used(k)),continue;endif
        % Differentiate one captured parameter as the sole predictor. A fresh
        % program identity is required; never mutate a frozen fit declaration.
        probe=struct('kind','expression','expression',{{regexprep(model.expression{1},['\<' ids{k} '\>'],'gx_query')}},'parameter_ids',{model.parameter_ids},'parameters',model.parameters,'predictor_ids',{{'gx_query'}});
        derivative=gxtxt_numeric_v1('nonlinear_evaluate',probe,values(k),struct('predictor_derivative',true));
        if(!derivative.derivative_valid(1)),row.derivative_valid=false;else J(i,j)=derivative.predictor_derivative(1);endif
      endfor
    catch err
      if((isempty(err.identifier)||strcmp(err.identifier,'GXTXT:Numeric:Ceres'))&&strcmp(strtrim(err.message),'GXTXT:Numeric:Ceres: nonfinite prediction'))
        row.value_status='undefined';row.reason='Expression is outside its finite real domain';row.derivative_valid=false;
      else,rethrow(err);endif
    end_try_catch
    if(strcmp(row.value_status,'value')&&row.derivative_valid&&strcmp(plan.status,'value')),available(end+1)=i;endif
    rows{i}=row;
  endfor
  propagation='';
  if(!isempty(available))
    C=plan.source_covariance;
    if(!isequal(size(C),[numel(free),numel(free)])),fail('Captured covariance shape differs from free parameter identities');endif
    propagation=gxtxt_numeric_v1('propagate_uncertainty',J(available,:),C,struct('input_kind','covariance'));
  endif
  out=struct('numeric_api','NUMERIC_API_v1','operation','derived_properties','plan',plan,'properties',{rows},'propagation_indices',available(:),'propagation',propagation,'derivative_method','two_sided_automatic_differentiation','fit_performed',false);
endfunction
function value=items(value)
  if(isempty(value)),value={};elseif(isstruct(value)),value=num2cell(value);elseif(!iscell(value)),fail('Expected a list of declarations');endif
endfunction
function value=celltext(value)
  if(ischar(value)),value={value};endif
  if(!iscellstr(value)),fail('Expected declared text identities');endif
endfunction
function fail(message),error('GXTXT:Numeric:DerivedProperties',message);endfunction
