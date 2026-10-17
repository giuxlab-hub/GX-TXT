% Public bounded data-only expressions; reuse the CORE grammar, units and Numeric.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_expression_v1(operation,varargin)
  root=fullfile(fileparts(mfilename('fullpath')),'..','..','..','..','..');
  addpath(fullfile(root,'core/octave/analysis'));addpath(fullfile(root,'core/octave/units'));addpath(fullfile(root,'core/octave/io'));
  if(strcmp(operation,'dataset'))
    out=dataset_evaluate(varargin{:});return;
  endif
  if(strcmp(operation,'evaluate'))
    expression=varargin{1};symbols=varargin{2};units=varargin{3};options=struct();if(numel(varargin)>3),options=varargin{4};endif
    validate_options(options,{'output_unit'});
    [values,unit,dimensions]=evaluate(expression,symbols,units,field(options,'output_unit',''));
    out=struct('schema','gxtxt.numeric_expression.v1','values',values,'unit',unit,'dimensions',dimensions,...
      'expression',expression,'symbol_ids',{fieldnames(symbols)},'domain_policy','finite_real_or_error',...
      'grammar_owner','CORE gxtxt_analysis_expression_parse','numeric_owner','NUMERIC_API_v1');return;
  endif
  if(!strcmp(operation,'analyze')),fail('Unknown expression operation');endif
  request=varargin{1};options=struct();if(numel(varargin)>1),options=varargin{2};endif
  validate_options(options,{'sample_count','max_evaluations','max_iterations','x_tolerance','response_tolerance','output_unit'});
  validate_options(request,{'expression','expression2','variable','interval','symbols','symbol_units','mode'});
  expression=required(request,'expression');variable=required(request,'variable');interval=required(request,'interval');
  symbols=field(request,'symbols',struct());units=required(request,'symbol_units');mode=field(request,'mode','roots');
  if(!ischar(variable)||isempty(regexp(variable,'^[A-Za-z_][A-Za-z0-9_]*$','once'))||any(strcmp(variable,{'pi','e'}))),fail('Invalid independent variable identity');endif
  if(!isnumeric(interval)||!isreal(interval)||numel(interval)!=2||any(!isfinite(interval))||interval(1)>=interval(2)),fail('Explicit finite increasing interval required');endif
  if(!any(strcmp(mode,{'roots','intersections','extrema'}))),fail('Mode must be roots, intersections or extrema');endif
  if(!isstruct(symbols)||!isstruct(units)||!isfield(units,variable)),fail('Explicit symbol units including the independent variable are required');endif
  for name=fieldnames(symbols).',if(numel(symbols.(name{1}))!=1),fail('Analysis parameters must be scalar');endif,endfor
  samples=integer_option(options,'sample_count',129,5,4097);budget=integer_option(options,'max_evaluations',8192,samples,65536);
  iterations=integer_option(options,'max_iterations',128,1,256);
  xtol=positive_option(options,'x_tolerance',1e-9);ytol=positive_option(options,'response_tolerance',1e-9);
  target_unit=field(options,'output_unit','');second='';if(strcmp(mode,'intersections')),second=required(request,'expression2');endif
  evaluations=0;failures={};roots=[];residual=[];root_kind={};extrema_x=[];extrema_y=[];extrema_kind={};
  x=linspace(interval(1),interval(2),samples).';y=objective(x);
  if(strcmp(mode,'extrema'))
    for i=2:samples-1
      if(evaluations>=budget),break;endif
      polarity=0;
      if(y(i)<y(i-1)&&y(i)<=y(i+1)),polarity=1;elseif(y(i)>y(i-1)&&y(i)>=y(i+1)),polarity=-1;endif
      if(!polarity),continue;endif
      try
        r=gxtxt_numeric_v1('minimize_1d',@(q) polarity*objective(q),[x(i-1),x(i+1)],struct('tolerance',xtol,'max_iterations',iterations));
        if(!r.converged),fail('Local extremum did not converge');endif
        value=objective(r.x);
        if(isempty(extrema_x)||all(abs(extrema_x-r.x)>8*xtol))
          extrema_x(end+1,1)=r.x;extrema_y(end+1,1)=value;
          kind='minimum';if(polarity<0),kind='maximum';endif;extrema_kind{end+1,1}=kind;
        endif
      catch err,failures{end+1}=err.message;end_try_catch
    endfor
    status='local_extrema_found';if(isempty(extrema_x)),status='no_local_extremum_detected';endif
  else
    if(all(abs(y)<=ytol))
      status='indeterminate_sampled_zero';
    else
      for i=1:samples
        if(abs(y(i))<=ytol),append_root(x(i),y(i),'sample_residual_candidate');endif
      endfor
      for i=1:samples-1
        if(evaluations>=budget),break;endif
        if(sign(y(i))==sign(y(i+1))||y(i)==0||y(i+1)==0),continue;endif
        try
          r=gxtxt_numeric_v1('root_find',@objective,[x(i),x(i+1)],struct('tolerance',xtol,'max_iterations',iterations));
          value=objective(r.root);
          if(!r.converged||abs(value)>ytol),fail('Root candidate failed convergence or response tolerance (possible discontinuity)');endif
          append_root(r.root,value,'sign_change_verified');
        catch err,failures{end+1}=err.message;end_try_catch
      endfor
      % Even roots need not cross zero. Minimize |f| only in sampled local
      % valleys; report a residual-verified candidate, never a multiplicity proof.
      for i=2:samples-1
        if(evaluations>=budget),break;endif
        if(!(abs(y(i))<abs(y(i-1))&&abs(y(i))<=abs(y(i+1)))),continue;endif
        try
          r=gxtxt_numeric_v1('minimize_1d',@(q) abs(objective(q)),[x(i-1),x(i+1)],struct('tolerance',xtol,'max_iterations',iterations));
          value=objective(r.x);
          if(r.converged&&abs(value)<=ytol),append_root(r.x,value,'tangent_or_near_zero_candidate');endif
        catch err,failures{end+1}=err.message;end_try_catch
      endfor
      [roots,order]=sort(roots);residual=residual(order);root_kind=root_kind(order);
      status='roots_found';if(isempty(roots)),status='no_root_detected';endif
    endif
  endif
  if(evaluations>=budget),status='evaluation_budget_exhausted';elseif(!isempty(failures)),status=['partial_' status];endif
  out=struct('schema','gxtxt.numeric_expression_analysis.v1','mode',mode,'status',status,'expression',expression,...
    'expression2',second,'variable',variable,'interval',interval(:),'variable_unit',units.(variable),'response_unit',target_unit,...
    'roots',roots,'root_residuals',residual,'root_kinds',{root_kind},'extrema_x',extrema_x,'extrema_y',extrema_y,...
    'extrema_kinds',{extrema_kind},'domain_endpoints',interval(:),'endpoint_values',[y(1);y(end)],...
    'sample_count',samples,'function_evaluations',evaluations,'max_evaluations',budget,'x_tolerance',xtol,...
    'response_tolerance',ytol,'failures',{failures},'completeness','finite_sampling_is_not_a_completeness_proof',...
    'solver_owner','NUMERIC_API_v1 root_find/minimize_1d','uncertainty','not_estimated');

  function values=objective(q)
    if(evaluations+numel(q)>budget),error('GXTXT:Numeric:ExpressionBudget','Expression evaluation budget exhausted');endif
    evaluations+=numel(q);current=symbols;current.(variable)=q;
    [values,u]=evaluate(expression,current,units,target_unit);if(isempty(target_unit)),target_unit=u;endif
    if(!isempty(second)),other=evaluate(second,current,units,target_unit);values=values-other;endif
    if(isscalar(values)&&!isscalar(q)),values=repmat(values,size(q));endif
    if(numel(values)!=numel(q)),fail('Analysis expression must preserve independent-variable shape');endif
    values=reshape(values,size(q));
  endfunction
  function append_root(q,value,kind)
    if(q<interval(1)||q>interval(2)),fail('Solver candidate lies outside declared interval');endif
    if(isempty(roots)||all(abs(roots-q)>8*xtol)),roots(end+1,1)=q;residual(end+1,1)=value;root_kind{end+1,1}=kind;endif
  endfunction
endfunction

function out=dataset_evaluate(session,expression,bindings,parameters,options)
  if(nargin<5),options=struct();endif
  validate_options(options,{'start','count','output_unit'});
  if(!isstruct(bindings)||numel(bindings)!=1||isempty(fieldnames(bindings))||numel(fieldnames(bindings))>32||!isstruct(parameters)||numel(parameters)!=1),fail('Dataset expression requires1..32 symbol bindings and scalar parameter structure');endif
  start=field(options,'start',0);count=required(options,'count');
  if(!isnumeric(start)||numel(start)!=1||!isfinite(start)||start<0||start!=fix(start)||start>flintmax),fail('Invalid exact source row start');endif
  if(!isnumeric(count)||numel(count)!=1||!isfinite(count)||count<1||count>65536||count!=fix(count)),fail('Explicit row count1..65536 required');endif
  symbols=struct();units=struct();sources={};
  for item=fieldnames(parameters).'
    id=item{1};p=parameters.(id);validate_options(p,{'value','unit'});symbols.(id)=required(p,'value');units.(id)=required(p,'unit');
    if(numel(symbols.(id))!=1),fail('Dataset expression parameters must be scalar');endif
  endfor
  for item=fieldnames(bindings).'
    id=item{1};if(isfield(symbols,id)),fail('Parameter and Dataset symbol identities must be distinct');endif
    binding=bindings.(id);validate_options(binding,{'dataset_id','variable_id'});
    dataset=required(binding,'dataset_id');variable=required(binding,'variable_id');
    stream=gxtxt_table_stream_open_dataset(session,dataset,{variable},min(4096,count),struct('start',start,'count',count));values=[];
    unwind_protect
      metadata=gxtxt_table_stream_metadata(stream);vars=metadata.variables;if(iscell(vars)),vars=[vars{:}];endif
      found=find(strcmp({vars.variable_id},variable));if(numel(found)!=1),fail('Dataset Variable identity is unavailable');endif
      unit=vars(found).unit;if(isempty(unit)),fail('Dataset expression requires explicit unit metadata; dimensionless must be1');endif
      while(true)
        [stream,chunk]=gxtxt_table_stream_next(stream);
        if(chunk.nrows<1),if(chunk.eof),break;else continue;endif,endif
        if(isfield(chunk,'missing_masks')&&!isempty(chunk.missing_masks)&&any(chunk.missing_masks{1}(:))),fail('Missing Dataset observations require an explicit upstream selection');endif
        column=gxtxt_table_chunk_column(chunk,variable);if(!isnumeric(column)),fail('Dataset mathematical Variables must have a real numeric dtype');endif
        if(isinteger(column)&&any(abs(double(column(:)))>2^53)),fail('Dataset integer values cannot be represented exactly as binary64 mathematical inputs');endif
        values=[values;column(:)];if(numel(values)>count),fail('Public Dataset read exceeded declared count');endif
        if(chunk.eof),break;endif
      endwhile
    unwind_protect_cleanup
      gxtxt_table_stream_close(stream);
    end_unwind_protect
    if(numel(values)!=count),fail('Dataset source does not cover the complete declared row range');endif
    symbols.(id)=values;units.(id)=unit;
    sources{end+1}=struct('symbol',id,'dataset_id',dataset,'variable_id',variable,'unit',unit,'row_start',uint64(start),'row_count',uint64(count),'row_mapping','absolute_source_order');
  endfor
  out=gxtxt_numeric_expression_v1('evaluate',expression,symbols,units,struct('output_unit',field(options,'output_unit','')));
  out.sources=sources;out.parameter_metadata=parameters;out.alignment='caller_explicit_same_row_positions_no_inferred_time_or_frame_alignment';
endfunction

function [values,unit,dimensions]=evaluate(expression,symbols,units,output_unit)
  if(!ischar(expression)||isempty(expression)||numel(expression)>8192||!isstruct(symbols)||numel(symbols)!=1||!isstruct(units)||numel(units)!=1),fail('Bounded expression text and scalar symbol/unit structures required');endif
  names=fieldnames(symbols);if(numel(names)>64),fail('At most64 symbols are permitted');endif
  count=1;
  for i=1:numel(names)
    id=names{i};value=symbols.(id);
    if(isempty(regexp(id,'^[A-Za-z_][A-Za-z0-9_]*$','once'))||any(strcmp(id,{'pi','e'}))),fail('Invalid or reserved symbol identity');endif
    if(!isnumeric(value)||!isreal(value)||isempty(value)||!isvector(value)||any(!isfinite(value(:)))||numel(value)>65536),fail('Symbols require bounded nonempty finite real scalars/vectors');endif
    if(isinteger(value)&&any(abs(double(value(:)))>2^53)),fail('Integer expression input outside exact binary64 range is unsupported');endif
    if(numel(value)>1&&count>1&&numel(value)!=count),fail('Vector symbol lengths must agree');endif
    count=max(count,numel(value));symbols.(id)=double(value(:));
  endfor
  tokens=gxtxt_analysis_expression_parse(expression);if(numel(tokens)>1024),fail('Expression exceeds1024 shared grammar tokens');endif
  for i=1:numel(tokens)
    t=tokens{i};if(strcmp(t.kind,'func'))
      meta=gxtxt_numeric_v1('operation_by_expression_name',t.text);
      if(!strcmp(meta.category,'elementwise')),fail('Only registered pointwise mathematical functions are allowed');endif
    endif
  endfor
  symbols.pi=pi;symbols.e=exp(1);units.pi='1';units.e='1';
  dimensions=gxtxt_numeric_v1('expression_dimensions',expression,units,output_unit);
  [values,unit]=gxtxt_analysis_expression_strict_units(expression,symbols,units,output_unit);
  if(!isnumeric(values)||!isreal(values)||any(!isfinite(values(:)))),fail('Expression result is outside its finite real domain');endif
endfunction
function validate_options(value,allowed)
  if(!isstruct(value)||numel(value)!=1),fail('Request/options must be scalar structures');endif
  for name=fieldnames(value).',if(!any(strcmp(name{1},allowed))),fail(['Unknown request option ' name{1}]);endif,endfor
endfunction
function value=field(s,name,default),value=default;if(isfield(s,name)),value=s.(name);endif,endfunction
function value=required(s,name),if(!isfield(s,name)),fail(['Required field missing: ' name]);endif;value=s.(name);endfunction
function value=positive_option(s,name,default),value=field(s,name,default);if(!isnumeric(value)||!isreal(value)||numel(value)!=1||!isfinite(value)||value<=0),fail(['Positive finite ' name ' required']);endif,endfunction
function value=integer_option(s,name,default,lo,hi),value=positive_option(s,name,default);if(value!=fix(value)||value<lo||value>hi),fail(['Out-of-range integer ' name]);endif,endfunction
function fail(message),error('GXTXT:Numeric:Expression',message);endfunction
