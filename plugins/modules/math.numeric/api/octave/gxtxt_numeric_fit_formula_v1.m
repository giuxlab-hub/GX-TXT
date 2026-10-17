% SPDX-License-Identifier: GPL-3.0-or-later
% Data-only formula declaration using CORE grammar/units and the existing fit VM.
function model=gxtxt_numeric_fit_formula_v1(action,request)
  if(strcmp(action,'compose')),model=compose(request);return;endif
  if(!strcmp(action,'validate')||!isstruct(request)||numel(request)!=1||!isfield(request,'formula_declaration')),fail('Invalid formula declaration action');endif
  declaration=request.formula_declaration;
  if(!isstruct(declaration)||!isfield(declaration,'schema')||!strcmp(declaration.schema,'gxtxt.fit_formula_declaration.v1')||!isfield(declaration,'recipe')),fail('Unversioned formula declaration');endif
  rebuilt=compose(declaration.recipe);
  for key={'expression','parameter_ids','parameter_units','predictor_ids','response_units','parameter_constraints','input_constraints','formula_declaration'}
    name=key{1};if(!isfield(request,name)),fail(['Retained formula lacks ' name]);endif
    actual=request.(name);expected=rebuilt.(name);
    if(strcmp(name,'formula_declaration')&&isfield(actual,'dimensional_receipt')&&isfield(actual.dimensional_receipt,'inferred_parameter_ids')&&isempty(actual.dimensional_receipt.inferred_parameter_ids))
      % Existing Script numeric-argument transport represents an empty list as
      % an empty numeric vector. This specific string-list field has no values;
      % normalize only that empty representation, preserving every other fact.
      actual.dimensional_receipt.inferred_parameter_ids={};
    endif
    if(strcmp(name,'formula_declaration')&&isfield(actual,'dimensional_receipts'))
      receipts=actual.dimensional_receipts;if(isstruct(receipts)),receipts=num2cell(receipts);endif
      if(iscell(receipts))
        for k=1:numel(receipts)
          if(isstruct(receipts{k})&&isfield(receipts{k},'inferred_parameter_ids')&&isempty(receipts{k}.inferred_parameter_ids)),receipts{k}.inferred_parameter_ids={};endif
        endfor
        actual.dimensional_receipts=reshape(receipts,1,[]);
      endif
    endif
    if(!isequaln(actual,expected)),fail(['Retained formula differs from its immutable declaration: ' name]);endif
  endfor
  if(isfield(request,'parameters'))
    values=request.parameters(:);c=rebuilt.parameter_constraints;
    if(numel(values)!=numel(c.initial_parameters)||any(!isfinite(values))||any(values<c.lower_bounds)||any(values>c.upper_bounds)||any(values(logical(c.fixed_mask))!=c.initial_parameters(logical(c.fixed_mask))))
      fail('Retained formula parameters violate their declared constraints');
    endif
  endif
  model=request;
endfunction
function model=compose(recipe,allow_unused=false)
  if(isstruct(recipe)&&isfield(recipe,'expression')&&iscell(recipe.expression)),model=compose_responses(recipe);return;endif
  keys(recipe,{'expression','predictor_ids','predictor_units','response_unit','parameters'},'formula recipe');
  for name={'expression','predictor_ids','predictor_units','response_unit','parameters'}
    if(!isfield(recipe,name{1})),fail(['Formula recipe requires ' name{1}]);endif
  endfor
  formula=recipe.expression;inputs=recipe.predictor_ids;input_units=recipe.predictor_units;response_unit=recipe.response_unit;parameters=recipe.parameters;
  if(ischar(inputs)),inputs={inputs};endif;if(ischar(input_units)),input_units={input_units};endif
  if(isstruct(parameters)),parameters=num2cell(parameters);endif
  if(!ischar(formula)||isempty(formula)||numel(formula)>32768||!iscellstr(inputs)||isempty(inputs)||numel(inputs)>32||numel(unique(inputs))!=numel(inputs)||!iscellstr(input_units)||numel(input_units)!=numel(inputs)||!iscell(parameters)||isempty(parameters)||numel(parameters)>128)
    fail('Formula requires bounded text, 1..32 named predictors and 1..128 named parameters');
  endif
  here=fileparts(mfilename('fullpath'));root=fullfile(here,'..','..','..','..','..');
  addpath(fullfile(root,'core','octave','analysis'));addpath(fullfile(root,'core','octave','units'));addpath(fullfile(root,'core','octave','io'));
  tokens=gxtxt_analysis_expression_parse(formula);functions={};
  for i=1:numel(tokens),if(strcmp(tokens{i}.kind,'func')),functions{end+1}=tokens{i}.text;endif,endfor
  ids=cell(1,numel(parameters));units=struct();unknown={};n=numel(parameters);initial=zeros(n,1);lower=-Inf(n,1);upper=Inf(n,1);fixed=zeros(n,1);
  for i=1:numel(inputs)
    identity(inputs{i},functions);units.(inputs{i})=input_units{i};parsed=gxtxt_unit_parse(input_units{i});
    if(!ischar(input_units{i})||isempty(strtrim(input_units{i}))||!strcmp(parsed.kind,'linear')||!isfinite(parsed.scale)||parsed.scale<=0),fail('Formula predictors require explicit linear units');endif
  endfor
  for i=1:n
    item=parameters{i};keys(item,{'id','unit','initial','lower','upper','fixed'},'formula parameter');
    if(!isfield(item,'id')||!isfield(item,'initial')),fail('Formula parameter requires id and initial');endif
    id=item.id;identity(id,functions);ids{i}=id;
    if(any(strcmp(id,inputs))||any(strcmp(id,ids(1:i-1)))),fail('Formula parameter identities must be unique and separate from predictors');endif
    initial(i)=scalar(item.initial,'initial',false);
    if(isfield(item,'lower')),lower(i)=scalar(item.lower,'lower',true);endif
    if(isfield(item,'upper')),upper(i)=scalar(item.upper,'upper',true);endif
    if(isfield(item,'fixed')),fixed(i)=scalar(item.fixed,'fixed',false);if(!any(fixed(i)==[0,1])),fail('Fixed must be zero or one');endif;endif
    if(lower(i)>upper(i)||initial(i)<lower(i)||initial(i)>upper(i)),fail('Formula initial value violates its declared bounds');endif
    if(lower(i)==upper(i)),fixed(i)=1;endif
    unit='';if(isfield(item,'unit')),unit=item.unit;endif
    if(!ischar(unit)),fail('Parameter unit must be text or empty for inference');endif
    if(isempty(strtrim(unit))),unknown{end+1}=id;else units.(id)=unit;endif
  endfor
  dimensional=gxtxt_unit_expression_dimensions_v1(formula,units,response_unit,unknown);
  if(!allow_unused&&!all(ismember(ids,dimensional.used_symbols))),fail('Every declared fitted parameter must occur in the formula');endif
  resolved_units=cell(1,n);for i=1:n,resolved_units{i}=dimensional.symbol_units.(ids{i});endfor
  % Apply immutable unit scales inside the existing expression program. Fitted
  % coefficients and covariance remain in each declared parameter's own units.
  effective=formula;names=[inputs(:);ids(:)];
  for i=1:numel(names)
    name=names{i};if(!isfield(dimensional.symbol_scales,name)),continue;endif;scale=dimensional.symbol_scales.(name);
    if(scale!=1),effective=regexprep(effective,['\<' name '\>'],sprintf('(%.17g*%s)',scale,name));endif
  endfor
  if(dimensional.output_scale!=1),effective=sprintf('(%s)/%.17g',effective,dimensional.output_scale);endif
  constraints=struct('initial_parameters',initial,'lower_bounds',lower,'upper_bounds',upper,'fixed_mask',fixed);
  input=struct('domain','finite_real','translation_policy','forbid_translation','required_x_unit','','required_y_unit',response_unit);
  if(numel(inputs)==1),input.required_x_unit=input_units{1};endif
  model=struct('kind','expression','expression',{{effective}},'parameter_ids',{ids},'parameter_units',{resolved_units},...
    'predictor_ids',{reshape(inputs,1,[])},'response_units',{{response_unit}},'initial_parameters',initial,'parameters',initial);
  % Validate only the existing program grammar here; no optimizer or trial
  % scientific calculation runs while declaring the model.
  [unused,model]=gxtxt_numeric_fit_program_v1(model,numel(inputs),n);
  model.parameter_constraints=constraints;model.input_constraints=input;
  model.formula_declaration=struct('schema','gxtxt.fit_formula_declaration.v1','recipe',recipe,'original_expression',formula,...
    'effective_expression',effective,'dimensional_receipt',dimensional,'derivative_policy','existing_native_expression_vm_analytic_with_explicit_nonsmooth_domains',...
    'unit_policy','physical_parameter_units_with_explicit_internal_SI_conversion','source_expression_sha256',hash('sha256',formula));
endfunction
function keys(value,allowed,label)
  if(!isstruct(value)||numel(value)!=1),fail([label ' must be one data struct']);endif
  unknown=setdiff(fieldnames(value),allowed);if(!isempty(unknown)),fail(['Unknown ' label ' field: ' unknown{1}]);endif
endfunction
function identity(value,functions)
  if(!ischar(value)||isempty(regexp(value,'^[A-Za-z_][A-Za-z0-9_]*$','once'))||numel(value)>64||any(strcmp(value,{'pi','e'}))||any(strcmp(value,functions))),fail('Invalid, reserved or function-colliding formula symbol');endif
endfunction
function value=scalar(value,label,infinite)
  if(!(isnumeric(value)||islogical(value))||!isreal(value)||!isscalar(value)||isnan(value)||(!infinite&&!isfinite(value))),fail(['Invalid formula parameter ' label]);endif
  value=double(value);
endfunction
function fail(message),error('GXTXT:Numeric:Formula','%s',message);endfunction

function model=compose_responses(recipe)
  keys(recipe,{'expression','predictor_ids','predictor_units','response_unit','parameters'},'multi-response formula recipe');
  expressions=recipe.expression;units=recipe.response_unit;parameters=recipe.parameters;
  if(isstruct(parameters)),parameters=num2cell(parameters);endif
  if(!iscellstr(expressions)||numel(expressions)<2||numel(expressions)>32||!iscellstr(units)||numel(units)!=numel(expressions)||!iscell(parameters)||isempty(parameters)),fail('Multiple formulas require2..32 expressions, matching response units and named parameters');endif
  for k=1:numel(parameters)
    if(!isfield(parameters{k},'unit')||!ischar(parameters{k}.unit)||isempty(strtrim(parameters{k}.unit))),fail('Shared multi-response parameters require explicit physical units');endif
  endfor
  parts=cell(1,numel(expressions));effective=parts;receipts=parts;used={};
  for k=1:numel(expressions)
    one=recipe;one.expression=expressions{k};one.response_unit=units{k};
    parts{k}=compose(one,true);effective{k}=parts{k}.expression{1};receipts{k}=parts{k}.formula_declaration.dimensional_receipt;
    used=union(used,receipts{k}.used_symbols);
  endfor
  model=parts{1};
  if(!all(ismember(model.parameter_ids,used))),fail('Every shared parameter must occur in at least one response formula');endif
  % Individual responses may omit shared parameters. Compile their dimensional
  % declarations independently, then bind one common physical parameter order.
  model=rmfield(model,'formula_declaration');model.expression=effective;model.response_units=reshape(units,1,[]);
  model.input_constraints.required_y_unit='';
  model.formula_declaration=struct('schema','gxtxt.fit_formula_declaration.v1','recipe',recipe,...
    'original_expression',{reshape(expressions,1,[])},'effective_expression',{effective},'dimensional_receipts',{receipts},...
    'derivative_policy','existing_native_expression_vm_analytic_with_explicit_nonsmooth_domains',...
    'unit_policy','physical_parameter_units_with_explicit_internal_SI_conversion','source_expression_sha256',hash('sha256',jsonencode(expressions)));
  % Compiler identity includes every response; validation checks the whole recipe.
  bare=rmfield(model,{'formula_declaration','input_constraints'});
  [unused,bare]=gxtxt_numeric_fit_program_v1(bare,numel(model.predictor_ids),numel(model.parameter_ids));
  for field={'source_sha256','binding_sha256'},model.(field{1})=bare.(field{1});endfor
endfunction
