% One joint declared model from frozen regional increment descriptors.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_fit_regions_v1(action,request,varargin)
  switch(action)
    case 'catalog'
      out=struct('schema','gxtxt.fit_region_catalog.v1','models',{read_catalog()});
    case 'compose'
      out=compose(request,read_catalog());
    case 'validate'
      out=request;scalar_struct(out,'model');
      c=out.regional_composition;scalar_struct(c,'regional composition');
      if(!isfield(c,'schema')||!strcmp(c.schema,'gxtxt.fit_regions.v1')),fail('Unsupported regional schema');endif
      rebuilt=compose(c.recipe,c.cards);
      for key={'expression','parameter_ids','parameter_units','predictor_ids'}
        if(!isfield(out,key{1})||!isequal(text_list(out.(key{1})),text_list(rebuilt.(key{1})))),fail('Saved regional model differs from its frozen declaration');endif
      endfor
      if(!isfield(out,'parameter_constraints')||!isfield(out,'input_constraints')||!isequal(out.input_constraints,rebuilt.input_constraints)),fail('Saved regional model lost or changed its constraints');endif
      for key={'initial_parameters','lower_bounds','upper_bounds','fixed_mask'}
        if(!isfield(out.parameter_constraints,key{1})||!isequal(out.parameter_constraints.(key{1})(:),rebuilt.parameter_constraints.(key{1})(:))),fail('Saved regional parameter constraints changed');endif
      endfor
      if(isfield(out,'parameters'))
        v=number(out.parameters,numel(rebuilt.parameter_ids),'saved parameters',false);b=rebuilt.parameter_constraints;f=logical(b.fixed_mask);
        if(any(v<b.lower_bounds)||any(v>b.upper_bounds)||any(v(f)!=b.initial_parameters(f))),fail('Saved regional parameters violate frozen constraints');endif
      endif
    case 'selection'
      out=selection(gxtxt_numeric_fit_regions_v1('validate',request),varargin{1});
    otherwise
      fail('Unknown regional model action');
  endswitch
endfunction

function cards=read_catalog()
  root=fileparts(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))));
  addpath(fullfile(root,'core','octave','io'));
  paths=dir(fullfile(root,'plugins','models','*','model.ini'));cards={};ids={};
  if(numel(paths)>512),fail('Model descriptor count exceeds 512');endif
  for k=1:numel(paths)
    path=fullfile(paths(k).folder,paths(k).name);
    if(paths(k).bytes>65536),fail('Model descriptor exceeds 64 KiB');endif
    d=gxtxt_ini_read(path,true);if(!isKey(d,'regional_fit.api_version')),continue;endif
    if(!strcmp(required(d,'meta.api_version'),'1')||!strcmp(required(d,'regional_fit.api_version'),'1')||!strcmp(required(d,'meta.kind'),'regional_increment')),fail('Unsupported regional descriptor version or kind');endif
    card=struct('id',required(d,'meta.id'),'version',required(d,'meta.version'), ...
      'name',required(d,'meta.name'),'description',required(d,'meta.description'),'descriptor_sha256',hash('sha256',fileread(path)));
    for key={'increment','derivative','initialization','uncertainty','extrapolation'}
      card.(key{1})=required(d,['regional_fit.',key{1}]);
    endfor
    for key={'parameter_ids','parameter_units','parameter_meanings','parameter_domains'}
      card.(key{1})=strsplit(required(d,['regional_fit.',key{1}]),';');
    endfor
    card.initial_parameters=cellfun(@str2double,strsplit(required(d,'regional_fit.initial_parameters'),';'))(:);
    card.definition_sha256=card_digest(card);card=validate_card(card);
    if(any(strcmp(ids,card.id))),fail('Duplicate regional descriptor identity');endif
    ids{end+1}=card.id;cards{end+1}=card;
  endfor
endfunction

function card=validate_card(card)
  scalar_struct(card,'descriptor');
  for key={'id','version','name','description','descriptor_sha256','increment','derivative','initialization','uncertainty','extrapolation'}
    if(!isfield(card,key{1})),fail('Incomplete regional descriptor');endif
    text(card.(key{1}),key{1},4096);
  endfor
  if(isempty(regexp(card.id,'^[a-z][a-z0-9_.]*$','once'))||isempty(regexp(card.descriptor_sha256,'^[a-f0-9]{64}$','once'))),fail('Invalid regional descriptor identity');endif
  for key={'parameter_ids','parameter_units','parameter_meanings','parameter_domains'}
    if(!isfield(card,key{1})),fail('Incomplete regional parameter descriptor');endif
    card.(key{1})=text_list(card.(key{1}));
  endfor
  ids=card.parameter_ids;p=numel(ids);
  if(p<1||p>8||numel(unique(ids))!=p||!strcmp(ids{1},'slope')),fail('Regional descriptors need 1..8 distinct parameters, first named slope');endif
  for j=1:p,symbol(ids{j});if(strcmp(ids{j},'t')),fail('Regional span t is reserved');endif;endfor
  for key={'parameter_units','parameter_meanings','parameter_domains'}
    if(numel(card.(key{1}))!=p),fail('Regional parameter fields differ in length');endif
  endfor
  if(!strcmp(card.parameter_units{1},'Y/X')||!all(ismember(card.parameter_units,{'Y/X','1/X','Y/X^2','Y/X^3'}))||!all(strcmp(card.parameter_domains,'real'))),fail('Unsupported regional units or parameter domains');endif
  card.initial_parameters=number(card.initial_parameters,p,'descriptor initial',false);
  if(!isfield(card,'definition_sha256')||!ischar(card.definition_sha256)||!strcmp(card.definition_sha256,card_digest(card))),fail('Frozen regional descriptor definition digest differs');endif
endfunction

function digest=card_digest(card)
  values={};
  for key={'id','version','name','description','descriptor_sha256','increment','derivative','initialization','uncertainty','extrapolation'}
    values{end+1}=card.(key{1});
  endfor
  for key={'parameter_ids','parameter_units','parameter_meanings','parameter_domains'},values{end+1}=text_list(card.(key{1}));endfor
  values{end+1}=arrayfun(@(v)sprintf('%.17g',v),card.initial_parameters(:).','UniformOutput',false);
  digest=hash('sha256',jsonencode(values));
endfunction

function model=compose(recipe,cards)
  scalar_struct(recipe,'recipe');keys(recipe,{'x_unit','y_unit','origin','regions','breakpoints','fit_windows','parameters'});
  for key={'x_unit','y_unit','origin','regions','breakpoints'},if(!isfield(recipe,key{1})),fail(['Regional recipe requires ',key{1}]);endif;endfor
  text(recipe.x_unit,'x_unit',128);text(recipe.y_unit,'y_unit',128);recipe.origin=number(recipe.origin,1,'origin',false);
  regions=struct_list(recipe.regions);breaks=struct_list(recipe.breakpoints);n=numel(regions);
  if(n<2||n>8||numel(breaks)!=n-1),fail('A regional model needs 2..8 regions and exactly one breakpoint between neighbours');endif
  cards=struct_list(cards);card_ids=cellfun(@(c)c.id,cards,'UniformOutput',false);
  if(numel(unique(card_ids))!=numel(card_ids)),fail('Duplicate frozen descriptor identity');endif
  ids={'level'};units={recipe.y_unit};initial=0;lower=-Inf;upper=Inf;fixed=0;break_ids={};region_ids={};
  for k=1:n-1
    b=breaks{k};keys(b,{'id','initial','lower','upper','fixed','continuity'});
    for key={'id','initial','lower','upper','fixed','continuity'},if(!isfield(b,key{1})),fail(['Breakpoint requires ',key{1}]);endif;endfor
    symbol(b.id);if(any(strcmp(ids,b.id))),fail('Duplicate breakpoint/parameter identity');endif
    for key={'initial','lower','upper','fixed'},b.(key{1})=number(b.(key{1}),1,['breakpoint ',key{1}],false);endfor
    if(!ismember(b.fixed,[0,1])||b.lower>b.upper||b.initial<b.lower||b.initial>b.upper|| ...
        !ischar(b.continuity)||!any(strcmp(b.continuity,{'C0','C1'}))),fail('Invalid breakpoint bounds, initial value, fixed flag or continuity');endif
    if(k==1&&recipe.origin>b.lower||k>1&&breaks{k-1}.upper>=b.lower),fail('Breakpoint search windows must be ordered and disjoint, with origin at or before the first lower bound');endif
    if(b.lower==b.upper),b.fixed=1;endif
    breaks{k}=b;break_ids{end+1}=b.id;ids{end+1}=b.id;units{end+1}=recipe.x_unit;
    initial(end+1,1)=b.initial;lower(end+1,1)=b.lower;upper(end+1,1)=b.upper;fixed(end+1,1)=b.fixed;
  endfor
  used_cards={};used_ids={};terms={'level'};end_slope='';
  for k=1:n
    r=regions{k};keys(r,{'id','model_id'});
    if(!isfield(r,'id')||!isfield(r,'model_id')),fail('Each region needs id and model_id');endif
    symbol(r.id);text(r.model_id,'model_id',128);
    if(any(strcmp(region_ids,r.id))),fail('Duplicate region identity');endif
    region_ids{end+1}=r.id;index=find(strcmp(card_ids,r.model_id));if(numel(index)!=1),fail('Unknown regional descriptor');endif
    card=validate_card(cards{index});
    if(!any(strcmp(used_ids,card.id))),used_ids{end+1}=card.id;used_cards{end+1}=card;endif
    local=card.parameter_ids;bindings=cell(size(local));
    for j=1:numel(local)
      if(j==1&&k>1&&strcmp(breaks{k-1}.continuity,'C1'))
        bindings{j}=['(',end_slope,')'];continue;
      endif
      name=[r.id,'_',local{j}];symbol(name);if(any(strcmp(ids,name))),fail('Regional parameter identity collides with an existing parameter');endif
      ids{end+1}=name;bindings{j}=name;units{end+1}=parameter_unit(card.parameter_units{j},recipe.x_unit,recipe.y_unit);
      initial(end+1,1)=card.initial_parameters(j);lower(end+1,1)=-Inf;upper(end+1,1)=Inf;fixed(end+1,1)=0;
    endfor
    if(k==1)
      start=sprintf('%.17g',recipe.origin);span=['(minimum(x,',break_ids{1},')-(',start,'))'];
    elseif(k==n)
      start=break_ids{k-1};span=['positive_part(x-',start,')'];
    else
      start=break_ids{k-1};span=['positive_part(minimum(x,',break_ids{k},')-',start,')'];
    endif
    terms{end+1}=['(',substitute(card.increment,[local,{'t'}],[bindings,{['(',span,')']}]),')'];
    if(k<n),length_expression=['(',break_ids{k},'-(',start,'))'];end_slope=substitute(card.derivative,[local,{'t'}],[bindings,{length_expression}]);endif
  endfor
  overrides=struct();if(isfield(recipe,'parameters')),overrides=recipe.parameters;scalar_struct(overrides,'parameter overrides');keys(overrides,ids);endif
  for j=1:numel(ids)
    if(!isfield(overrides,ids{j})),continue;endif
    if(any(strcmp(break_ids,ids{j}))),fail('Breakpoint settings belong in breakpoints, not parameter overrides');endif
    o=overrides.(ids{j});scalar_struct(o,'parameter override');keys(o,{'initial','lower','upper','fixed'});
    if(isfield(o,'initial')),initial(j)=number(o.initial,1,'initial',false);endif
    if(isfield(o,'lower')),lower(j)=number(o.lower,1,'lower',true);endif
    if(isfield(o,'upper')),upper(j)=number(o.upper,1,'upper',true);endif
    if(isfield(o,'fixed')),fixed(j)=number(o.fixed,1,'fixed',false);if(!ismember(fixed(j),[0,1])),fail('Fixed must be boolean');endif;endif
  endfor
  if(any(lower>upper)||any(initial<lower)||any(initial>upper)),fail('Initial parameters and bounds are inconsistent');endif
  windows=zeros(0,2);
  if(isfield(recipe,'fit_windows')&&!isempty(recipe.fit_windows))
    windows=recipe.fit_windows;
    if(!isnumeric(windows)||!isreal(windows)||columns(windows)!=2||rows(windows)>64||any(!isfinite(windows(:)))||any(windows(:,1)>windows(:,2))||any(windows(2:end,1)<windows(1:end-1,2))),fail('Fit windows must be up to 64 ordered nonoverlapping finite [lower,upper] pairs; touching endpoints are allowed');endif
    windows=double(windows);
  endif
  expression=strjoin(terms,'+');if(numel(expression)>32768),fail('Regional expression exceeds 32768 characters');endif
  recipe.regions=regions;recipe.breakpoints=breaks;recipe.parameters=overrides;recipe.fit_windows=windows;
  model=struct('kind','expression','expression',{{expression}},'parameter_ids',{ids},'predictor_ids',{{'x'}}, ...
    'parameter_units',{units},'initial_parameters',initial,'parameters',initial, ...
    'parameter_constraints',struct('initial_parameters',initial,'lower_bounds',lower,'upper_bounds',upper,'fixed_mask',fixed), ...
    'input_constraints',struct('domain','finite_real','required_x_unit',recipe.x_unit,'required_y_unit',recipe.y_unit,'translation_policy','forbid_translation'), ...
    'regional_composition',struct('schema','gxtxt.fit_regions.v1','recipe',recipe,'cards',{used_cards}));
  if(numel(jsonencode(model))>131072),fail('Regional model metadata exceeds 128 KiB');endif
endfunction

function out=selection(model,x)
  if(!isnumeric(x)||!isreal(x)||(!isvector(x)&&!isempty(x))),fail('Region selection requires one real predictor vector');endif
  x=double(x(:));r=model.regional_composition.recipe;windows=r.fit_windows;
  selected=isfinite(x);
  if(!isempty(windows))
    selected=false(size(x));for k=1:rows(windows),selected=selected|(x>=windows(k,1)&x<=windows(k,2));endfor
    selected=selected&isfinite(x);
  endif
  breaks=struct_list(r.breakpoints);q=model.parameters;region=ones(size(x));values=zeros(numel(breaks),1);
  for k=1:numel(breaks)
    values(k)=q(find(strcmp(model.parameter_ids,breaks{k}.id)));region=region+(x>=values(k));
  endfor
  region(!selected)=0;counts=zeros(numel(breaks)+1,1);
  for k=1:numel(counts),counts(k)=sum(region==k);endfor
  out=struct('schema','gxtxt.fit_region_selection.v1','selected_mask',selected,'source_row_positions',find(selected), ...
    'region_indices',region,'region_counts',counts,'breakpoint_values',values,'input_count',numel(x), ...
    'retained_count',sum(selected),'excluded_count',sum(!selected),'index_base',1, ...
    'boundary_ownership','right_region','fit_windows',windows);
endfunction

function result=substitute(formula,local,bindings)
  [starts,ends,tokens]=regexp(formula,'[A-Za-z_][A-Za-z0-9_]*','start','end','match');result=formula;
  for k=numel(tokens):-1:1
    j=find(strcmp(local,tokens{k}));if(!isempty(j)),result=[result(1:starts(k)-1),bindings{j},result(ends(k)+1:end)];endif
  endfor
endfunction
function unit=parameter_unit(role,x,y)
  switch(role)
    case 'Y/X',unit=[y,'/(',x,')'];
    case '1/X',unit=['1/(',x,')'];
    case 'Y/X^2',unit=[y,'/(',x,')^2'];
    case 'Y/X^3',unit=[y,'/(',x,')^3'];
  endswitch
endfunction
function value=required(d,key)
  if(!isKey(d,key)||isempty(d(key))),fail(['Descriptor field missing: ',key]);endif;value=d(key);
endfunction
function scalar_struct(s,label)
  if(!isstruct(s)||numel(s)!=1),fail([label,' must be a scalar data struct']);endif
endfunction
function keys(s,allowed)
  scalar_struct(s,'declaration');if(!all(ismember(fieldnames(s),allowed))),fail('Unknown regional declaration field');endif
endfunction
function text(v,label,limit)
  if(!ischar(v)||rows(v)!=1||isempty(v)||numel(v)>limit||any(v==0)||any(v==10)||any(v==13)),fail(['Invalid ',label]);endif
endfunction
function symbol(v)
  text(v,'identity',128);
  if(isempty(regexp(v,'^[A-Za-z_][A-Za-z0-9_]*$','once'))||any(strcmp(v,{'x','pi','e'}))),fail('Invalid or reserved identity');endif
endfunction
function values=text_list(values)
  if(ischar(values)),values={values};endif
  if(!iscellstr(values)),fail('Expected text list');endif;values=values(:).';
  for k=1:numel(values),text(values{k},'list item',32768);endfor
endfunction
function values=struct_list(values)
  if(isstruct(values)),values=num2cell(values);endif
  if(!iscell(values)),fail('Expected region/breakpoint/descriptor list');endif;values=values(:).';
  for k=1:numel(values),scalar_struct(values{k},'list element');endfor
endfunction
function value=number(value,n,label,allow_infinity)
  if((!isnumeric(value)&&!islogical(value))||!isreal(value)||numel(value)!=n||any(isnan(value(:)))||(!allow_infinity&&any(!isfinite(value(:))))),fail(['Invalid ',label,' vector']);endif
  value=double(value(:));
endfunction
function fail(message),error('GXTXT:Numeric:FitRegions','%s',message);endfunction
