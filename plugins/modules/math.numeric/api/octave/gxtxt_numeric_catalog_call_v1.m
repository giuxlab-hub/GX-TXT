% Data-only catalog dispatcher for the public NUMERIC_API_v1 Tcl binding.
% SPDX-License-Identifier: GPL-3.0-or-later
function out = gxtxt_numeric_catalog_call_v1(operation, mode, operands, unused_b, unused_c, options)
  if(!strcmp(mode,'invoke') || !iscell(operands) || !isstruct(options))
    error('GXTXT:Numeric:InvalidArguments','catalog call requires typed operands and options');
  endif
  parts = strsplit(operation,'.');
  base = parts{1};
  args = operands(:).';
  if(numel(parts)>1)
    if(!any(strcmp(base,{'array_unary','array_binary','array_compare','array_mask','array_reduce','complex_unary','complex_binary'})))
      error('GXTXT:Numeric:UnknownOperation','grouped catalog operation is unsupported');
    endif
    action = strjoin(parts(2:end),'.');
    args = [{action},args];
  endif
  if(isempty(fieldnames(options)))
    out = gxtxt_numeric_v1(base,args{:});
  else
    % These public fits place optional weights before options. Retain an
    % explicit empty slot when a catalog caller supplies options without weights.
    if(any(strcmp(base,{'least_squares','linear_regression'}))&&numel(args)==2)
      args{3}=[];
    elseif(strcmp(base,'polynomial_fit')&&numel(args)==3)
      args{4}=[];
    endif
    out = gxtxt_numeric_v1(base,args{:},options);
  endif
  if(!isstruct(out))
    out = struct('value',out);
  endif
endfunction
