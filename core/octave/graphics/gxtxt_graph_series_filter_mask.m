function keep=gxtxt_graph_series_filter_mask(ch,filters)
% Apply AND-composed source-value predicates to one bounded Table Stream chunk.
% SPDX-License-Identifier: GPL-3.0-or-later
  keep=true(ch.nrows,1);
  for j=1:numel(filters)
    f=filters{j};id=f.filter_variable_id;predicate=f.predicate;
    if(strcmp(f.dtype,'string'))
      values=gxtxt_table_chunk_column(ch,id);
      if(!iscell(values)),values=cellstr(values);endif
      switch(predicate)
        case 'exact_equal',match=strcmp(values,f.value);
        case 'not_equal',match=!strcmp(values,f.value);
        case 'in_set'
          match=false(ch.nrows,1);
          for k=1:numel(f.values),match|=strcmp(values,f.values{k});endfor
        otherwise,error('GXTXT:GraphSeries','predicate %s is invalid for text variable %s',predicate,id);
      endswitch
    else
      integer=!isempty(regexp(f.dtype,'^(u?int(8|16|32|64)|bool)$','once'));
      if(integer)
        values=gxtxt_table_integer_values_v1(gxtxt_table_chunk_column(ch,id),f.dtype);
        parse=@(s)gxtxt_table_integer_values_v1(s,f.dtype);
      else values=double(gxtxt_table_chunk_numeric(ch,id));parse=@str2double;endif
      values=values(:);
      switch(predicate)
        case 'exact_equal',match=values==parse(f.value);
        case 'not_equal',match=values!=parse(f.value);
        case 'less_than',match=values<parse(f.value);
        case 'less_equal',match=values<=parse(f.value);
        case 'greater_than',match=values>parse(f.value);
        case 'greater_equal',match=values>=parse(f.value);
        case 'between_inclusive',match=values>=parse(f.lower)&values<=parse(f.upper);
        case 'in_set'
          match=false(ch.nrows,1);
          for k=1:numel(f.values),match|=values==parse(f.values{k});endfor
        case 'is_finite',match=isfinite(values);
        case 'is_nonfinite',match=!isfinite(values);
        otherwise,error('GXTXT:GraphSeries','unsupported row predicate %s',predicate);
      endswitch
    endif
    keep&=match(:);
  endfor
endfunction
