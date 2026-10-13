% Controlled expression grammar shared by numeric and unit-aware evaluation.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_analysis_expression_parse(expression)
  tokens=tokenize(expression);
  out=to_rpn(tokens);
endfunction

function tokens=tokenize(s)
  tokens={};i=1;n=length(s);prev='start';
  while(i<=n)
    c=s(i);if(isspace(c)),i+=1;continue;endif
    rest=s(i:end);
    m=regexp(rest,'^((([0-9]+(\.[0-9]*)?)|(\.[0-9]+))([eE][+-]?[0-9]+)?)','match','once');
    if(!isempty(m))
      tokens{end+1}=struct('kind','num','text',m);i+=length(m);prev='value';continue;
    endif
    m=regexp(rest,'^([A-Za-z_][A-Za-z0-9_]*)','match','once');
    if(!isempty(m))
      tail=strtrim(rest(length(m)+1:end));
      if(!isempty(tail)&&tail(1)=='('),kind='func';prev='func';else kind='id';prev='value';endif
      tokens{end+1}=struct('kind',kind,'text',m);i+=length(m);continue;
    endif
    if(c=='(')
      tokens{end+1}=struct('kind','lpar','text','(');i+=1;prev='lpar';continue;
    elseif(c==')')
      tokens{end+1}=struct('kind','rpar','text',')');i+=1;prev='value';continue;
    elseif(c==',')
      tokens{end+1}=struct('kind','comma','text',',');i+=1;prev='comma';continue;
    elseif(any(c=='+-*/^'))
      op=c;if((c=='-'||c=='+')&&any(strcmp(prev,{'start','op','lpar','comma'}))),op=['u' c];endif
      tokens{end+1}=struct('kind','op','text',op);i+=1;prev='op';continue;
    endif
    error('GXTXT:AnalysisExpression','Unsupported character in expression: %s',c);
  endwhile
  if(isempty(tokens)),error('GXTXT:AnalysisExpression','Empty expression');endif
endfunction

function p=precedence(op)
  switch(op)
    case '^',p=4;
    case {'u-','u+'},p=3;
    case {'*','/'},p=2;
    case {'+','-'},p=1;
    otherwise,p=0;
  endswitch
endfunction
function tf=right_associative(op),tf=any(strcmp(op,{'^','u-','u+'}));endfunction

function out=to_rpn(tokens)
  out={};stack={};
  for i=1:numel(tokens)
    q=tokens{i};
    if(any(strcmp(q.kind,{'num','id'})))
      out{end+1}=q;
    elseif(strcmp(q.kind,'func'))
      stack{end+1}=q;
    elseif(strcmp(q.kind,'op'))
      if(any(strcmp(q.text,{'u-','u+'})))
        stack{end+1}=q;continue;
      endif
      while(!isempty(stack)&&strcmp(stack{end}.kind,'op'))
        top=stack{end};
        if((!right_associative(q.text)&&precedence(q.text)<=precedence(top.text))|| ...
           (right_associative(q.text)&&precedence(q.text)<precedence(top.text)))
          out{end+1}=top;stack(end)=[];
        else break;endif
      endwhile
      stack{end+1}=q;
    elseif(strcmp(q.kind,'lpar'))
      q.argc=0;stack{end+1}=q;
    elseif(strcmp(q.kind,'comma'))
      found=false;
      while(!isempty(stack))
        if(strcmp(stack{end}.kind,'lpar')),found=true;break;endif
        out{end+1}=stack{end};stack(end)=[];
      endwhile
      if(!found||numel(stack)<2||!strcmp(stack{end-1}.kind,'func'))
        error('GXTXT:AnalysisExpression','Comma outside a function call');
      endif
      stack{end}.argc+=1;
    elseif(strcmp(q.kind,'rpar'))
      found=false;
      while(!isempty(stack))
        if(strcmp(stack{end}.kind,'lpar')),paren=stack{end};stack(end)=[];found=true;break;endif
        out{end+1}=stack{end};stack(end)=[];
      endwhile
      if(!found),error('GXTXT:AnalysisExpression','Mismatched parentheses');endif
      if(!isempty(stack)&&strcmp(stack{end}.kind,'func'))
        f=stack{end};stack(end)=[];
        if(strcmp(tokens{i-1}.kind,'lpar')),f.argc=0;else f.argc=paren.argc+1;endif
        out{end+1}=f;
      endif
    endif
  endfor
  while(!isempty(stack))
    if(any(strcmp(stack{end}.kind,{'lpar','func'}))),error('GXTXT:AnalysisExpression','Mismatched parentheses');endif
    out{end+1}=stack{end};stack(end)=[];
  endwhile
endfunction
