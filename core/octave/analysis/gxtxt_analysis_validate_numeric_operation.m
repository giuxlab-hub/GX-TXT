% Validate a discoverable NUMERIC_API expression call from public metadata.
% SPDX-License-Identifier: GPL-3.0-or-later
function gxtxt_analysis_validate_numeric_operation(meta,args)
  name=meta.expression_name;
  n=numel(args);
  if(n<meta.arity_min||n>meta.arity_max)
    error('GXTXT:AnalysisExpression','Function %s expects %d to %d arguments',name,meta.arity_min,meta.arity_max);
  endif
  if(!any(strcmp(meta.bindings,'octave')))
    error('GXTXT:AnalysisExpression','Function %s is unavailable in the Octave binding',name);
  endif
  option_index=0;
  if(!isempty(meta.expression_option_argument)&&n>meta.arity_min),option_index=n;endif
  ordinary=args;
  if(option_index),ordinary(end)=[];endif
  allowed=meta.accepted_kinds;
  universal=all(cellfun(@(kind) any(strcmp(kind,{'scalar','vector','matrix','mask'})),allowed));
  if(universal)
    for i=1:numel(ordinary)
      kind=shape_kind(ordinary{i});
      if(!any(strcmp(allowed,kind)))
        error('GXTXT:AnalysisExpression','Function %s argument %d has unsupported %s shape',name,i,kind);
      endif
    endfor
  endif
  if(option_index&&!isscalar(args{end}))
    error('GXTXT:AnalysisExpression','Function %s option argument must be scalar',name);
  endif
  shape=meta.shape_semantics;
  switch(shape)
    case {'same_length','same_length_xy','value_and_probability_vectors'}
      if(numel(ordinary)>=2)
        if(!isvector(ordinary{1})||!isvector(ordinary{2})||numel(ordinary{1})!=numel(ordinary{2}))
          if(!strcmp(shape,'value_and_probability_vectors'))
            error('GXTXT:AnalysisExpression','Function %s requires equal-length vector inputs',name);
          endif
        endif
      endif
    case 'equal_shape_or_scalar'
      reference=[];
      for i=1:numel(ordinary)
        if(isscalar(ordinary{i})),continue;endif
        if(isempty(reference)),reference=size(ordinary{i});
        elseif(!isequal(reference,size(ordinary{i})))
          error('GXTXT:AnalysisExpression','Function %s requires equal array shapes or scalars',name);
        endif
      endfor
    case 'scalar_parameters'
      for i=1:numel(ordinary)
        if(!isscalar(ordinary{i}))
          error('GXTXT:AnalysisExpression','Function %s argument %d must be scalar',name,i);
        endif
      endfor
  endswitch
endfunction

function kind=shape_kind(value)
  if(isscalar(value)),kind='scalar';
  elseif(isvector(value)),kind='vector';
  elseif(ismatrix(value)),kind='matrix';
  else kind='other';endif
endfunction
