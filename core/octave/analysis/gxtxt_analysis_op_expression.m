% Controlled Scientific Analysis expression evaluator using NUMERIC_API_v1.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_analysis_op_expression(expr,series)
  rpn=gxtxt_analysis_expression_parse(expr);
  stack={};
  for i=1:numel(rpn)
    token=rpn{i};
    if(strcmp(token.kind,'num'))
      stack{end+1}=str2double(token.text);
    elseif(strcmp(token.kind,'id'))
      if(!isfield(series,token.text)),error('GXTXT:AnalysisExpression','Unknown symbol: %s',token.text);endif
      value=series.(token.text);
      if(!isnumeric(value)||!isreal(value)),error('GXTXT:AnalysisExpression','Symbol %s is not real numeric',token.text);endif
      stack{end+1}=value;
    elseif(strcmp(token.kind,'op'))
      if(any(strcmp(token.text,{'u-','u+'})))
        if(isempty(stack)),error('GXTXT:AnalysisExpression','Missing unary operand');endif
        value=stack{end};stack(end)=[];
        if(strcmp(token.text,'u-'))
          result=gxtxt_analysis_numeric_call('array_unary','negate',value);
          value=result.values;
        endif
        stack{end+1}=value;
      else
        if(numel(stack)<2),error('GXTXT:AnalysisExpression','Missing binary operand');endif
        right=stack{end};stack(end)=[];left=stack{end};stack(end)=[];
        switch(token.text)
          case '+',name='add';
          case '-',name='subtract';
          case '*',name='multiply';
          case '/',name='divide';
          case '^',name='power';
          otherwise,error('GXTXT:AnalysisExpression','Unsupported operator: %s',token.text);
        endswitch
        result=gxtxt_analysis_numeric_call('array_binary',name,left,right);
        stack{end+1}=result.values;
      endif
    elseif(strcmp(token.kind,'func'))
      meta=gxtxt_analysis_numeric_call('operation_by_expression_name',token.text);
      if(numel(stack)<token.argc),error('GXTXT:AnalysisExpression','Missing function argument');endif
      args=stack(end-token.argc+1:end);stack(end-token.argc+1:end)=[];
      for j=1:numel(args)
        if(!isnumeric(args{j})||!isreal(args{j}))
          error('GXTXT:AnalysisExpression','Function %s requires real numeric arguments',token.text);
        endif
      endfor
      gxtxt_analysis_validate_numeric_operation(meta,args);
      if(!isempty(meta.expression_option_argument)&&numel(args)>meta.arity_min)
        options=struct();options.(meta.expression_option_argument)=args{end};args(end)=[];
        args{end+1}=options;
      endif
      parts=strsplit(meta.id,'.');
      if(numel(parts)==2)
        result=gxtxt_analysis_numeric_call(parts{1},parts{2},args{:});
      else
        result=gxtxt_analysis_numeric_call(meta.id,args{:});
      endif
      field=meta.expression_result_field;
      if(!isstruct(result)||!isfield(result,field))
        error('GXTXT:AnalysisExpression','Function %s returned no %s field',token.text,field);
      endif
      stack{end+1}=result.(field);
    endif
  endfor
  if(numel(stack)!=1),error('GXTXT:AnalysisExpression','Invalid expression');endif
  out=stack{1};
endfunction
