% Shared expression grammar with Unit Registry dimensional validation.
% SPDX-License-Identifier: GPL-3.0-or-later
function [out,out_unit]=gxtxt_analysis_expression_strict_units(expr,series,units,output_unit)
  if(nargin<4),output_unit='';endif
  rpn=gxtxt_analysis_expression_parse(expr);scaled=series;used={};
  for i=1:numel(rpn)
    token=rpn{i};if(!strcmp(token.kind,'id')),continue;endif
    id=token.text;if(any(strcmp(used,id))),continue;endif;used{end+1}=id;
    if(!isfield(series,id)),error('GXTXT:AnalysisUnits','unknown symbol: %s',id);endif
    unit='';if(isfield(units,id)),unit=units.(id);endif
    if(isempty(strtrim(unit))),error('GXTXT:AnalysisUnits','strict unit checking requires unit metadata for %s',id);endif
    parsed=gxtxt_unit_parse(unit);
    if(!strcmp(parsed.kind,'linear')),error('GXTXT:AnalysisUnits','strict unit arithmetic does not support semantic/non-linear unit %s',unit);endif
    if(!isnumeric(series.(id))||!isreal(series.(id))),error('GXTXT:AnalysisUnits','strict unit expression requires real numeric series: %s',id);endif
    scaled.(id)=series.(id).*parsed.scale;
  endfor
  dimensions=eval_dimensions(rpn,units);
  out=gxtxt_analysis_op_expression(expr,scaled);
  if(!isempty(strtrim(output_unit)))
    target=gxtxt_unit_parse(output_unit);
    if(!strcmp(target.kind,'linear')),error('GXTXT:AnalysisUnits','strict unit arithmetic does not support semantic/non-linear output unit %s',output_unit);endif
    if(!same_dims(dimensions.dims,target.dims)),error('GXTXT:AnalysisUnits','expression result is incompatible with requested unit %s',output_unit);endif
    out=out./target.scale;out_unit=output_unit;
  else
    out_unit=dims_label(dimensions.dims);
  endif
endfunction

function result=eval_dimensions(rpn,units)
  stack={};
  for i=1:numel(rpn)
    token=rpn{i};
    if(strcmp(token.kind,'num'))
      stack{end+1}=struct('dims',struct(),'const',str2double(token.text));
    elseif(strcmp(token.kind,'id'))
      parsed=gxtxt_unit_parse(units.(token.text));
      stack{end+1}=struct('dims',parsed.dims,'const',NaN);
    elseif(strcmp(token.kind,'op'))
      if(any(strcmp(token.text,{'u-','u+'})))
        if(isempty(stack)),error('GXTXT:AnalysisUnits','missing unary operand');endif
        if(strcmp(token.text,'u-')),stack{end}.const=-stack{end}.const;endif
        continue;
      endif
      if(numel(stack)<2),error('GXTXT:AnalysisUnits','missing binary operand');endif
      right=stack{end};stack(end)=[];left=stack{end};stack(end)=[];
      switch(token.text)
        case {'+','-'}
          if(!same_dims(left.dims,right.dims)),error('GXTXT:AnalysisUnits','incompatible dimensions in %s operation',token.text);endif
          dims=left.dims;
        case '*',dims=combine(left.dims,right.dims,1);
        case '/',dims=combine(left.dims,right.dims,-1);
        case '^',dims=power_dims(left,right);
        otherwise,error('GXTXT:AnalysisUnits','unsupported operator %s',token.text);
      endswitch
      stack{end+1}=struct('dims',dims,'const',NaN);
    elseif(strcmp(token.kind,'func'))
      meta=gxtxt_analysis_numeric_call('operation_by_expression_name',token.text);
      if(token.argc<meta.arity_min||token.argc>meta.arity_max||numel(stack)<token.argc)
        error('GXTXT:AnalysisUnits','invalid function arity for %s',token.text);
      endif
      args=stack(end-token.argc+1:end);stack(end-token.argc+1:end)=[];
      behavior=meta.unit_behavior;dims=struct();
      switch(behavior)
        case 'preserve'
          dims=args{1}.dims;
          if(numel(args)>1&&!isempty(fieldnames(args{2}.dims)))
            error('GXTXT:AnalysisUnits','function %s requires a dimensionless option',token.text);
          endif
        case 'compatible'
          dims=args{1}.dims;
          for j=2:numel(args)
            if(!same_dims(dims,args{j}.dims)),error('GXTXT:AnalysisUnits','incompatible function argument dimensions for %s',token.text);endif
          endfor
        case 'multiply',dims=combine(args{1}.dims,args{2}.dims,1);
        case 'divide',dims=combine(args{1}.dims,args{2}.dims,-1);
        case 'differentiate',dims=combine(args{2}.dims,args{1}.dims,-1);
        case 'square',dims=scale_dims(args{1}.dims,2);
        case 'square_root',dims=half_dims(args{1}.dims);
        case 'reciprocal',dims=scale_dims(args{1}.dims,-1);
        case 'power',dims=power_dims(args{1},args{2});
        case 'preserve_y'
          if(numel(args)<2),error('GXTXT:AnalysisUnits','function %s requires a Y series',token.text);endif
          dims=args{2}.dims;
          if(numel(args)>2&&!same_dims(args{1}.dims,args{3}.dims))
            error('GXTXT:AnalysisUnits','function %s target X unit is incompatible',token.text);
          endif
        case 'dimensionless_input_output'
          for j=1:numel(args)
            if(!isempty(fieldnames(args{j}.dims))),error('GXTXT:AnalysisUnits','function %s requires dimensionless input',token.text);endif
          endfor
        case 'dimensionless'
          for j=1:numel(args)
            if(!isempty(fieldnames(args{j}.dims))),error('GXTXT:AnalysisUnits','function %s requires dimensionless masks',token.text);endif
          endfor
        case 'compatible_to_dimensionless'
          for j=2:numel(args)
            if(!same_dims(args{1}.dims,args{j}.dims)),error('GXTXT:AnalysisUnits','function %s requires compatible input dimensions',token.text);endif
          endfor
        case 'dimensionless_output'
          % Predicates and count/index reductions do not carry source units.
        case 'power_by_count'
          if(!isempty(fieldnames(args{1}.dims)))
            error('GXTXT:AnalysisUnits','product reduction of dimensional data requires an explicit sample-count unit rule');
          endif
        otherwise
          error('GXTXT:AnalysisUnits','function %s has no declared unit rule',token.text);
      endswitch
      stack{end+1}=struct('dims',dims,'const',NaN);
    endif
  endfor
  if(numel(stack)!=1),error('GXTXT:AnalysisUnits','invalid unit expression');endif
  result=stack{1};
endfunction

function dims=power_dims(base,exponent)
  if(!isempty(fieldnames(exponent.dims))||!isfinite(exponent.const)||abs(exponent.const-round(exponent.const))>1e-12)
    error('GXTXT:AnalysisUnits','unit-aware exponent must be an integer numeric literal');
  endif
  dims=scale_dims(base.dims,round(exponent.const));
endfunction
function dims=half_dims(source)
  dims=source;names=fieldnames(dims);
  for i=1:numel(names)
    key=names{i};if(mod(dims.(key),2)!=0),error('GXTXT:AnalysisUnits','square root requires even unit exponents');endif
    dims.(key)=dims.(key)/2;if(dims.(key)==0),dims=rmfield(dims,key);endif
  endfor
endfunction
function tf=same_dims(a,b),tf=isequal(orderfields(a),orderfields(b));endfunction
function dims=combine(a,b,sign)
  dims=a;names=fieldnames(b);
  for i=1:numel(names)
    key=names{i};if(!isfield(dims,key)),dims.(key)=0;endif
    dims.(key)+=sign*b.(key);if(dims.(key)==0),dims=rmfield(dims,key);endif
  endfor
endfunction
function dims=scale_dims(source,power)
  dims=source;names=fieldnames(dims);
  for i=1:numel(names)
    key=names{i};dims.(key)*=power;if(dims.(key)==0),dims=rmfield(dims,key);endif
  endfor
endfunction
function text=dims_label(dims)
  names=sort(fieldnames(dims));if(isempty(names)),text='1';return;endif
  parts={};for i=1:numel(names)
    exponent=dims.(names{i});
    if(exponent==1),parts{end+1}=names{i};else parts{end+1}=sprintf('%s^%d',names{i},exponent);endif
  endfor
  text=strjoin(parts,'*');
endfunction
