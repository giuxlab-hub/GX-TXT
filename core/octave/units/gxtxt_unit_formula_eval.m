% SPDX-License-Identifier: GPL-3.0-or-later
% Safe arithmetic grammar for explicit unit conversions; no eval().
function out = gxtxt_unit_formula_eval(formula,x)
  compact=regexprep(formula,'\s+','');
  tokens=regexp(compact,'(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?|[A-Za-z_][A-Za-z_0-9]*|[()+*/^\-]','match');
  if(isempty(compact)||!strcmp(strjoin(tokens,''),compact)),error('GXTXT:UnitFormula','unsafe conversion formula');endif
  [out,i]=parse_sum(tokens,1,x);
  if(i<=numel(tokens)),error('GXTXT:UnitFormula','invalid conversion formula');endif
endfunction
function [v,i]=parse_sum(t,i,x)
  [v,i]=parse_product(t,i,x);
  while(i<=numel(t)&&any(strcmp(t{i},{'+','-'})))
    op=t{i}; i+=1; [rhs,i]=parse_product(t,i,x);
    if(strcmp(op,'+')),v=v+rhs;else v=v-rhs;endif
  endwhile
endfunction
function [v,i]=parse_product(t,i,x)
  [v,i]=parse_power(t,i,x);
  while(i<=numel(t)&&any(strcmp(t{i},{'*','/'})))
    op=t{i}; i+=1; [rhs,i]=parse_power(t,i,x);
    if(strcmp(op,'*')),v=v.*rhs;else v=v./rhs;endif
  endwhile
endfunction
function [v,i]=parse_power(t,i,x)
  [v,i]=parse_atom(t,i,x);
  if(i<=numel(t)&&strcmp(t{i},'^'))
    i+=1; [rhs,i]=parse_power(t,i,x); v=v.^rhs;
  endif
endfunction
function [v,i]=parse_atom(t,i,x)
  if(i>numel(t)),error('GXTXT:UnitFormula','incomplete conversion formula');endif
  q=t{i}; i+=1;
  if(strcmp(q,'+')||strcmp(q,'-'))
    [v,i]=parse_atom(t,i,x); if(strcmp(q,'-')),v=-v;endif; return;
  endif
  if(strcmp(q,'('))
    [v,i]=parse_sum(t,i,x);
    if(i>numel(t)||!strcmp(t{i},')')),error('GXTXT:UnitFormula','unclosed conversion formula');endif
    i+=1;return;
  endif
  if(any(strcmp(q,{'log','log10','exp','sqrt'})))
    if(i>numel(t)||!strcmp(t{i},'(')),error('GXTXT:UnitFormula','function requires parentheses');endif
    i+=1; [arg,i]=parse_sum(t,i,x);
    if(i>numel(t)||!strcmp(t{i},')')),error('GXTXT:UnitFormula','unclosed function');endif
    i+=1;
    switch q
      case 'log',v=log(arg);
      case 'log10',v=log10(arg);
      case 'exp',v=exp(arg);
      case 'sqrt',v=sqrt(arg);
    endswitch
    return;
  endif
  if(strcmp(q,'x')),v=x;return;endif
  v=str2double(q);
  if(isnan(v)),error('GXTXT:UnitFormula','unknown formula token');endif
endfunction
