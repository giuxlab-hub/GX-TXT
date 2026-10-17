% SPDX-License-Identifier: GPL-3.0-or-later
% Unit/Dimension API: shared grammar, structural dimensions and bounded inference.
% This does not evaluate scientific observations or fit model parameters.
function result=gxtxt_unit_expression_dimensions_v1(expression,units,output_unit,unknown_ids)
  if(nargin<3),output_unit='';endif
  if(nargin<4),unknown_ids={};endif
  if(!ischar(expression)||numel(expression)>32768||!isstruct(units)||numel(units)!=1||!ischar(output_unit)||!iscellstr(unknown_ids)||numel(unknown_ids)>128||numel(unique(unknown_ids))!=numel(unknown_ids))
    fail('Invalid or unbounded expression dimensional request');
  endif
  here=fileparts(mfilename('fullpath'));addpath(fullfile(here,'..','analysis'));
  tokens=gxtxt_analysis_expression_parse(expression);
  if(numel(tokens)>4096),fail('Expression dimensional program exceeds 4096 tokens');endif
  bases={'A','K','V','g','m','mol','s'};p=numel(unknown_ids);A=zeros(0,p);B=zeros(0,7);stack={};used={};scales=struct();known=struct();
  for k=1:numel(unknown_ids)
    id=unknown_ids{k};if(isempty(regexp(id,'^[A-Za-z_][A-Za-z0-9_]*$','once'))||isfield(units,id)||any(strcmp(id,{'pi','e'}))),fail('Unknown unit identities must be unique undeclared symbols');endif
  endfor
  names=fieldnames(units);
  referenced={};for k=1:numel(tokens),if(strcmp(tokens{k}.kind,'id')),referenced{end+1}=tokens{k}.text;endif,endfor
  for k=1:numel(names)
    id=names{k};if(!any(strcmp(id,referenced))),continue;endif
    parsed=parse_linear(units.(id));known.(id)=dimension_vector(parsed.dims,bases);scales.(id)=parsed.scale;
  endfor
  for k=1:numel(tokens)
    t=tokens{k};
    if(strcmp(t.kind,'num'))
      value=str2double(t.text);if(!isfinite(value)),fail('Nonfinite dimensional expression literal');endif
      stack{end+1}=node(zeros(1,p),zeros(1,7),value);
    elseif(strcmp(t.kind,'id'))
      id=t.text;index=find(strcmp(id,unknown_ids));
      if(!isempty(index)),coeff=zeros(1,p);coeff(index)=1;item=node(coeff,zeros(1,7),NaN);
      elseif(isfield(known,id)),item=node(zeros(1,p),known.(id),NaN);
      elseif(any(strcmp(id,{'pi','e'}))),value=pi;if(strcmp(id,'e')),value=exp(1);endif;item=node(zeros(1,p),zeros(1,7),value);
      else fail(['Missing unit metadata for ' id]);endif
      stack{end+1}=item;used{end+1}=id;
    elseif(strcmp(t.kind,'op'))
      if(any(strcmp(t.text,{'u-','u+'})))
        if(isempty(stack)),fail('Missing unary dimensional operand');endif
        if(strcmp(t.text,'u-')),stack{end}.constant=-stack{end}.constant;endif
        continue;
      endif
      if(numel(stack)<2),fail('Missing binary dimensional operand');endif
      right=stack{end};left=stack{end-1};stack(end-1:end)=[];
      switch(t.text)
        case {'+','-'}
          [A,B]=equal_units(A,B,left,right);item=left;
        case '*',item=combine(left,right,1);
        case '/',item=combine(left,right,-1);
        case '^',[item,A,B]=power_units(left,right,A,B);
        otherwise,fail('Unsupported dimensional operator');
      endswitch
      item.constant=constant_binary(t.text,left.constant,right.constant);
      stack{end+1}=item;
    elseif(strcmp(t.kind,'func'))
      meta=gxtxt_analysis_numeric_call('operation_by_expression_name',t.text);
      if(t.argc<meta.arity_min||t.argc>meta.arity_max||numel(stack)<t.argc),fail(['Invalid dimensional function arity: ' t.text]);endif
      args=stack(end-t.argc+1:end);stack(end-t.argc+1:end)=[];zero=node(zeros(1,p),zeros(1,7),NaN);
      switch(meta.unit_behavior)
        case 'preserve'
          item=args{1};if(numel(args)>1),[A,B]=equal_units(A,B,args{2},zero);endif
        case 'compatible'
          item=args{1};for j=2:numel(args),[A,B]=equal_units(A,B,item,args{j});endfor
        case 'multiply',item=combine(args{1},args{2},1);
        case 'divide',item=combine(args{1},args{2},-1);
        case 'differentiate',item=combine(args{2},args{1},-1);
        case 'square',item=multiply_units(args{1},2);
        case 'square_root',item=multiply_units(args{1},.5);
        case 'reciprocal',item=multiply_units(args{1},-1);
        case 'power',[item,A,B]=power_units(args{1},args{2},A,B);
        case 'preserve_y'
          if(numel(args)<2),fail('A response-preserving function requires two arguments');endif
          item=args{2};if(numel(args)>2),[A,B]=equal_units(A,B,args{1},args{3});endif
        case {'dimensionless_input_output','dimensionless'}
          for j=1:numel(args),[A,B]=equal_units(A,B,args{j},zero);endfor;item=zero;
        case 'compatible_to_dimensionless'
          for j=2:numel(args),[A,B]=equal_units(A,B,args{1},args{j});endfor;item=zero;
        case 'dimensionless_output',item=zero;
        case 'power_by_count',[A,B]=equal_units(A,B,args{1},zero);item=zero;
        otherwise,fail(['No registered unit rule for ' t.text]);
      endswitch
      item.constant=NaN;stack{end+1}=item;
    else fail('Unsupported dimensional token');endif
  endfor
  if(numel(stack)!=1),fail('Expression must yield exactly one dimensional result');endif
  final=stack{1};target=[];
  if(!isempty(strtrim(output_unit)))
    target=parse_linear(output_unit);[A,B]=equal_units(A,B,final,node(zeros(1,p),dimension_vector(target.dims,bases),NaN));
  endif
  if(any(!isfinite(A(:)))||any(!isfinite(B(:)))),fail('Dimensional constraints are not representable');endif
  inferred=zeros(p,7);
  if(p>0)
    if(isempty(A)),fail('Parameter units are underdetermined; declare them explicitly');endif
    % Bounded structural elimination over seven symbolic dimensions. Rows are
    % normalized to prevent literal integer powers changing pivot tolerances.
    divisor=max(abs(A),[],2);divisor(divisor==0)=1;M=[A./divisor,B./divisor];
    [R,pivots]=rref(M,1e-11);
    if(any(pivots>p)),fail('Incompatible dimensional constraints');endif
    if(numel(pivots)!=p),fail('Parameter units are underdetermined; declare ambiguous parameters explicitly');endif
    for j=1:p,inferred(pivots(j),:)=R(j,p+1:end);endfor
    if(max(abs(A*inferred-B)(:))>1e-9*max(1,max(abs(B(:))))),fail('Dimensional constraints cannot be resolved consistently');endif
    if(any(abs(inferred(:)-round(inferred(:)))>1e-9)),fail('Inferred parameter units require unsupported fractional dimensions; declare a physically normalized equation');endif
    inferred=round(inferred);
    for j=1:p
      id=unknown_ids{j};units.(id)=dimension_label(inferred(j,:),bases);scales.(id)=1;
    endfor
  elseif(!isempty(B)&&any(abs(B(:))>1e-11))
    fail('Incompatible dimensions in expression or requested output unit');
  endif
  dims=final.coefficients*inferred+final.dimensions;
  if(any(abs(dims-round(dims))>1e-9)),fail('Expression result requires unsupported fractional dimensions');endif
  dims=round(dims);label=dimension_label(dims,bases);map=struct();
  for j=1:7,if(dims(j)!=0),map.(bases{j})=dims(j);endif,endfor
  if(isempty(output_unit)),output_unit=label;output_scale=1;else output_scale=target.scale;endif
  result=struct('schema','gxtxt.expression_dimensions.v1','expression',expression,'symbol_units',units,'symbol_scales',scales,...
    'inferred_parameter_ids',{unknown_ids},'used_symbols',{unique(used)},'output_unit',output_unit,'output_scale',output_scale,...
    'dimensions',map,'dimension_label',label,'normalization','explicit_symbol_to_canonical_then_output_scale',...
    'variable_exponent_policy','dimensionless_base_and_exponent','constraint_count',rows(B));
endfunction
function U=parse_linear(unit)
  if(!ischar(unit)||isempty(strtrim(unit))),fail('Explicit nonempty linear unit metadata is required; use 1 for dimensionless');endif
  U=gxtxt_unit_parse(unit);
  if(!strcmp(U.kind,'linear')||!isfinite(U.scale)||U.scale<=0),fail(['Unsupported nonlinear, semantic, opaque or invalid unit: ' unit]);endif
endfunction
function v=dimension_vector(d,bases)
  if(!isempty(setdiff(fieldnames(d),bases))),fail('Unknown base dimension');endif
  v=zeros(1,7);for i=1:7,if(isfield(d,bases{i})),v(i)=d.(bases{i});endif,endfor
endfunction
function q=node(c,d,k),q=struct('coefficients',c,'dimensions',d,'constant',k);endfunction
function [A,B]=equal_units(A,B,left,right)
  A(end+1,:)=left.coefficients-right.coefficients;B(end+1,:)=right.dimensions-left.dimensions;
endfunction
function q=combine(a,b,sign),q=node(a.coefficients+sign*b.coefficients,a.dimensions+sign*b.dimensions,NaN);endfunction
function q=multiply_units(a,power),q=node(a.coefficients*power,a.dimensions*power,NaN);endfunction
function [q,A,B]=power_units(base,exponent,A,B)
  zero=node(zeros(size(base.coefficients)),zeros(1,7),NaN);[A,B]=equal_units(A,B,exponent,zero);
  value=exponent.constant;
  if(isfinite(value)&&value==fix(value))
    if(abs(value)>1024),fail('Dimensional exponent exceeds 1024');endif
    q=multiply_units(base,value);
  else
    [A,B]=equal_units(A,B,base,zero);q=zero;
  endif
endfunction
function value=constant_binary(op,a,b)
  value=NaN;if(!isfinite(a)||!isfinite(b)),return;endif
  switch(op)
    case '+',value=a+b;case '-',value=a-b;case '*',value=a*b;case '/',value=a/b;case '^',value=a^b;
  endswitch
  if(!isreal(value)||!isfinite(value)),value=NaN;endif
endfunction
function label=dimension_label(d,bases)
  parts={};for i=1:7
    if(d(i)==0),continue;endif
    if(d(i)==1),parts{end+1}=bases{i};else parts{end+1}=sprintf('%s^%d',bases{i},d(i));endif
  endfor
  label=strjoin(parts,'*');if(isempty(label)),label='1';endif
endfunction
function fail(message),error('GXTXT:UnitDimensions','%s',message);endfunction
