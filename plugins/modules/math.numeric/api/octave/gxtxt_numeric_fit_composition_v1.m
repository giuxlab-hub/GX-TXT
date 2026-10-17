% Data-only composition of independent plugins/models descriptors.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_fit_composition_v1(action,request)
  if(strcmp(action,'catalog'))
    out=struct('schema','gxtxt.fit_model_catalog.v1','models',{read_catalog()});return;
  endif
  if(strcmp(action,'validate'))
    out=request;scalar_struct(out,'model');
    c=out.composition;scalar_struct(c,'composition');
    if(!isfield(c,'schema')||!strcmp(c.schema,'gxtxt.fit_composition.v1')),fail('Unsupported composition schema');endif
    rebuilt=compose(c.recipe,c.cards);
    for key={'expression','parameter_ids','parameter_units'}
      if(!isfield(out,key{1})||!isequal(text_list(out.(key{1})),text_list(rebuilt.(key{1})))),fail('Saved composition differs from its frozen declaration');endif
    endfor
    if(!isfield(out,'parameter_constraints')),fail('Saved composition lost its parameter constraints');endif
    for key={'initial_parameters','lower_bounds','upper_bounds','fixed_mask'}
      if(!isfield(out.parameter_constraints,key{1})||!isequal(out.parameter_constraints.(key{1})(:),rebuilt.parameter_constraints.(key{1})(:))),fail('Saved composition constraints changed');endif
    endfor
    if(isfield(out,'input_constraints'))
      if(!isequal(out.input_constraints,rebuilt.input_constraints)),fail('Saved composition input constraints changed');endif
    elseif(!strcmp(rebuilt.input_constraints.domain,'finite_real')||!strcmp(rebuilt.input_constraints.translation_policy,'allowed')|| ...
        !isempty(rebuilt.input_constraints.required_x_unit)||!isempty(rebuilt.input_constraints.required_y_unit))
      fail('Saved physical composition lost its input constraints');
    endif
    % Older finite-real cards predate this additive contract; their digests and
    % frozen scientific definitions remain unchanged.
    out.input_constraints=rebuilt.input_constraints;
    if(isfield(out,'parameters'))
      values=numeric_vector(out.parameters,numel(rebuilt.parameter_ids),'saved parameters',false);bounds=rebuilt.parameter_constraints;
      if(any(values<bounds.lower_bounds)||any(values>bounds.upper_bounds)||any(values(logical(bounds.fixed_mask))!=bounds.initial_parameters(logical(bounds.fixed_mask))))
        fail('Saved parameters violate frozen component constraints');
      endif
    endif
    return;
  endif
  if(!strcmp(action,'compose')),fail('Unknown composition action');endif
  out=compose(request,read_catalog());
endfunction

function cards=read_catalog()
  root=fileparts(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))));
  addpath(fullfile(root,'core','octave','io'));
  paths=dir(fullfile(root,'plugins','models','*','model.ini'));cards={};ids={};
  if(numel(paths)>512),fail('Model descriptor count exceeds 512');endif
  for k=1:numel(paths)
    path=fullfile(paths(k).folder,paths(k).name);
    if(paths(k).bytes>65536),fail('Model descriptor exceeds 64 KiB');endif
    d=gxtxt_ini_read(path,true);
    if(!isKey(d,'fitting.api_version')),continue;endif
    if(!strcmp(required(d,'meta.api_version'),'1')||!strcmp(required(d,'fitting.api_version'),'1')),fail('Unsupported fitting descriptor version');endif
    card=struct('id',required(d,'meta.id'),'version',required(d,'meta.version'), ...
      'name',required(d,'meta.name'),'description',required(d,'meta.description'), ...
      'descriptor_sha256',hash('sha256',fileread(path)),'expression',required(d,'fitting.expression'), ...
      'parameter_ids',{strsplit(required(d,'parameters.names'),';')}, ...
      'parameter_units',{strsplit(required(d,'fitting.parameter_units'),';')}, ...
      'parameter_meanings',{strsplit(required(d,'fitting.parameter_meanings'),';')}, ...
      'parameter_domains',{strsplit(required(d,'fitting.parameter_domains'),';')}, ...
      'initial_parameters',cellfun(@str2double,strsplit(required(d,'parameters.initial'),';'))(:));
    for key={'predictor','method_class','input_domain','initialization','derivatives','uncertainty','extrapolation'}
      card.(key{1})=required(d,['fitting.',key{1}]);
    endfor
    for key={'required_x_unit','required_y_unit','translation_policy'}
      if(isKey(d,['fitting.',key{1}])),card.(key{1})=required(d,['fitting.',key{1}]);endif
    endfor
    card.definition_sha256=card_digest(card);
    card=validate_card(card);
    if(any(strcmp(ids,card.id))),fail('Duplicate fitting descriptor identity');endif
    ids{end+1}=card.id;cards{end+1}=card;
  endfor
endfunction

function card=validate_card(card)
  scalar_struct(card,'descriptor');
  for key={'id','version','name','description','descriptor_sha256','expression','predictor','method_class','input_domain','initialization','derivatives','uncertainty','extrapolation'}
    if(!isfield(card,key{1})),fail('Incomplete frozen descriptor');endif
    text(card.(key{1}),key{1},4096);
  endfor
  if(isempty(regexp(card.id,'^[a-z][a-z0-9_.]*$','once'))||isempty(regexp(card.descriptor_sha256,'^[a-f0-9]{64}$','once'))|| ...
      !strcmp(card.predictor,'x')||!strcmp(card.method_class,'regression')||!any(strcmp(card.input_domain,{'finite_real','positive_real'})))
    fail('Unsupported descriptor identity, domain or method class');
  endif
  for key={'required_x_unit','required_y_unit','translation_policy'}
    if(isfield(card,key{1})),text(card.(key{1}),key{1},128);endif
  endfor
  if(isfield(card,'translation_policy')&&!any(strcmp(card.translation_policy,{'allowed','forbid_input_translation','forbid_translation'}))),fail('Unsupported translation policy');endif
  for key={'parameter_ids','parameter_units','parameter_meanings','parameter_domains'}
    if(!isfield(card,key{1})),fail('Incomplete parameter descriptor');endif
    card.(key{1})=text_list(card.(key{1}));
  endfor
  ids=card.parameter_ids;p=numel(ids);
  if(p<1||p>32||numel(unique(ids))!=p),fail('Descriptor needs 1..32 distinct parameters');endif
  for j=1:p,symbol(ids{j});endfor
  for key={'parameter_units','parameter_meanings','parameter_domains'}
    if(numel(card.(key{1}))!=p),fail('Descriptor parameter fields differ in length');endif
  endfor
  if(!all(ismember(card.parameter_units,{'X','Y','Y/X','X/Y','Y*X','1','1/X'}))||!all(ismember(card.parameter_domains,{'real','positive','nonnegative'}))),fail('Unsupported parameter unit relationship or domain');endif
  card.initial_parameters=numeric_vector(card.initial_parameters,p,'initial',false);
  if(!isfield(card,'definition_sha256')||!ischar(card.definition_sha256)||!strcmp(card.definition_sha256,card_digest(card))),fail('Frozen descriptor definition digest differs');endif
endfunction

function digest=card_digest(card)
  values={};
  for key={'id','version','name','description','descriptor_sha256','expression','predictor','method_class','input_domain','initialization','derivatives','uncertainty','extrapolation'}
    values{end+1}=card.(key{1});
  endfor
  for key={'parameter_ids','parameter_units','parameter_meanings','parameter_domains'}
    values{end+1}=text_list(card.(key{1}));
  endfor
  values{end+1}=arrayfun(@(v)sprintf('%.17g',v),card.initial_parameters(:).','UniformOutput',false);
  for key={'required_x_unit','required_y_unit','translation_policy'}
    if(isfield(card,key{1})),values{end+1}={key{1},card.(key{1})};endif
  endfor
  digest=hash('sha256',jsonencode(values));
endfunction

function model=compose(recipe,cards)
  scalar_struct(recipe,'recipe');keys(recipe,{'components','x_unit','y_unit','parameters'});
  if(!isfield(recipe,'components')||!isfield(recipe,'x_unit')||!isfield(recipe,'y_unit')),fail('Composition requires components and explicit x_unit/y_unit');endif
  text(recipe.x_unit,'x_unit',128);text(recipe.y_unit,'y_unit',128);
  components=struct_list(recipe.components);
  if(isempty(components)||numel(components)>32),fail('Composition needs 1..32 components');endif
  cards=struct_list(cards);card_ids=cellfun(@(c)c.id,cards,'UniformOutput',false);
  if(numel(unique(card_ids))!=numel(card_ids)),fail('Duplicate frozen descriptor identity');endif
  ids={};units={};initial=[];lower=[];upper=[];fixed=[];terms={};component_ids={};used_cards={};used_ids={};normalized={};
  input=struct('domain','finite_real','required_x_unit','','required_y_unit','','translation_policy','allowed');
  for k=1:numel(components)
    c=components{k};scalar_struct(c,'component');keys(c,{'id','model_id','bindings','initial_parameters'});
    if(!isfield(c,'id')||!isfield(c,'model_id')),fail('Component requires its own id and model_id');endif
    symbol(c.id);text(c.model_id,'model_id',128);
    if(any(strcmp(component_ids,c.id))),fail('Duplicate component identity');endif
    component_ids{end+1}=c.id;index=find(strcmp(card_ids,c.model_id));
    if(numel(index)!=1),fail('Unknown model descriptor');endif
    card=validate_card(cards{index});
    if(strcmp(card.input_domain,'positive_real')),input.domain='positive_real';endif
    for axis={'x','y'}
      key=['required_',axis{1},'_unit'];
      if(isfield(card,key))
        if(!strcmp(card.(key),recipe.([axis{1},'_unit']))),fail(['Model ',card.id,' requires ',axis{1},' in ',card.(key)]);endif
        input.(key)=card.(key);
      endif
    endfor
    if(isfield(card,'translation_policy'))
      policies={'allowed','forbid_input_translation','forbid_translation'};
      input.translation_policy=policies{max(find(strcmp(policies,input.translation_policy)),find(strcmp(policies,card.translation_policy)))};
    endif
    if(!any(strcmp(used_ids,card.id))),used_ids{end+1}=card.id;used_cards{end+1}=card;endif
    local=card.parameter_ids;p=numel(local);bindings=struct();if(isfield(c,'bindings')),bindings=c.bindings;scalar_struct(bindings,'bindings');keys(bindings,local);endif
    values=card.initial_parameters;if(isfield(c,'initial_parameters')),values=numeric_vector(c.initial_parameters,p,'initial',false);endif
    global_ids=cell(1,p);
    for j=1:p
      name=[c.id,'_',local{j}];if(isfield(bindings,local{j})),name=bindings.(local{j});endif
      symbol(name);global_ids{j}=name;bindings.(local{j})=name;
      unit=parameter_unit(card.parameter_units{j},recipe.x_unit,recipe.y_unit);
      lo=-Inf;if(strcmp(card.parameter_domains{j},'positive')),lo=realmin;elseif(strcmp(card.parameter_domains{j},'nonnegative')),lo=0;endif
      if(values(j)<lo),fail('Initial parameter violates descriptor domain');endif
      index=find(strcmp(ids,name));
      if(isempty(index))
        ids{end+1}=name;units{end+1}=unit;initial(end+1,1)=values(j);lower(end+1,1)=lo;upper(end+1,1)=Inf;fixed(end+1,1)=0;
      else
        if(!strcmp(units{index},unit)||initial(index)!=values(j)),fail('Shared parameters require identical units and initial values');endif
        lower(index)=max(lower(index),lo);
      endif
    endfor
    terms{end+1}=['(',substitute(card.expression,local,global_ids),')'];
    c.bindings=bindings;c.initial_parameters=values;normalized{end+1}=c;
  endfor
  if(numel(ids)>128),fail('Composition exceeds 128 free/fixed parameter identities');endif
  overrides=struct();if(isfield(recipe,'parameters')),overrides=recipe.parameters;scalar_struct(overrides,'parameter overrides');keys(overrides,ids);endif
  for j=1:numel(ids)
    if(isfield(overrides,ids{j}))
      o=overrides.(ids{j});scalar_struct(o,'parameter override');keys(o,{'initial','lower','upper','fixed'});
      if(isfield(o,'initial')),initial(j)=numeric_vector(o.initial,1,'initial',false);endif
      if(isfield(o,'lower')),v=numeric_vector(o.lower,1,'lower',true);if(v<lower(j)),fail('Bounds cannot weaken the model domain');endif;lower(j)=v;endif
      if(isfield(o,'upper')),upper(j)=numeric_vector(o.upper,1,'upper',true);endif
      if(isfield(o,'fixed')),fixed(j)=numeric_vector(o.fixed,1,'fixed',false);if(!ismember(fixed(j),[0,1])),fail('Fixed must be boolean');endif;endif
    endif
  endfor
  if(any(lower>upper)||any(initial<lower)||any(initial>upper)),fail('Initial parameters and bounds are inconsistent');endif
  expression=strjoin(terms,'+');if(numel(expression)>32768),fail('Composite expression exceeds 32768 characters');endif
  recipe.components=normalized;recipe.parameters=overrides;
  model=struct('kind','expression','expression',{{expression}},'parameter_ids',{ids},'predictor_ids',{{'x'}}, ...
    'parameter_units',{units},'initial_parameters',initial,'parameters',initial, ...
    'parameter_constraints',struct('initial_parameters',initial,'lower_bounds',lower,'upper_bounds',upper,'fixed_mask',fixed), ...
    'input_constraints',input, ...
    'composition',struct('schema','gxtxt.fit_composition.v1','recipe',recipe,'cards',{used_cards}));
  if(numel(jsonencode(model))>131072),fail('Composite model metadata exceeds 128 KiB');endif
endfunction

function result=substitute(formula,local,global_ids)
  [starts,ends,tokens]=regexp(formula,'[A-Za-z_][A-Za-z0-9_]*','start','end','match');result=formula;
  for k=numel(tokens):-1:1
    j=find(strcmp(local,tokens{k}));if(!isempty(j)),result=[result(1:starts(k)-1),global_ids{j},result(ends(k)+1:end)];endif
  endfor
endfunction
function unit=parameter_unit(role,x,y)
  switch(role)
    case 'X',unit=x;
    case 'Y',unit=y;
    case 'Y/X',unit=[y,'/(',x,')'];
    case 'X/Y',unit=[x,'/(',y,')'];
    case 'Y*X',unit=[y,'*(',x,')'];
    case '1/X',unit=['1/(',x,')'];
    case '1',unit='1';
  endswitch
endfunction
function value=required(d,key)
  if(!isKey(d,key)||isempty(d(key))),fail(['Descriptor field missing: ',key]);endif;value=d(key);
endfunction
function scalar_struct(s,label)
  if(!isstruct(s)||numel(s)!=1),fail([label,' must be a scalar data struct']);endif
endfunction
function keys(s,allowed)
  if(!all(ismember(fieldnames(s),allowed))),fail('Unknown declaration field');endif
endfunction
function text(v,label,limit)
  if(!ischar(v)||rows(v)!=1||isempty(v)||numel(v)>limit||any(v==0)||any(v==10)||any(v==13)),fail(['Invalid ',label]);endif
endfunction
function symbol(v)
  text(v,'parameter/component identity',128);
  if(isempty(regexp(v,'^[A-Za-z_][A-Za-z0-9_]*$','once'))||any(strcmp(v,{'x','pi','e'}))),fail('Invalid or reserved parameter/component identity');endif
endfunction
function values=text_list(values)
  if(ischar(values)),values={values};endif
  if(!iscellstr(values)),fail('Expected text list');endif;values=values(:).';
  for k=1:numel(values),text(values{k},'list item',4096);endfor
endfunction
function values=struct_list(values)
  if(isstruct(values)),values=num2cell(values);endif
  if(!iscell(values)),fail('Expected component/descriptor list');endif;values=values(:).';
  for k=1:numel(values),scalar_struct(values{k},'list element');endfor
endfunction
function value=numeric_vector(value,n,label,allow_infinity)
  if((!isnumeric(value)&&!islogical(value))||!isreal(value)||numel(value)!=n||any(isnan(value(:)))||(!allow_infinity&&any(!isfinite(value(:))))),fail(['Invalid ',label,' vector']);endif
  value=double(value(:));
endfunction
function fail(message),error('GXTXT:Numeric:FitComposition','%s',message);endfunction
