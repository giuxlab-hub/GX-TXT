% SPDX-License-Identifier: GPL-3.0-or-later
% Table Stream API v2: return a typed numeric view; raw cells remain in chunk.values.
function v=gxtxt_table_chunk_numeric(chunk,name)
  c=gxtxt_table_chunk_column(chunk,name);v=nan(numel(c),1);
  if(isnumeric(c)||islogical(c)),v=double(c);return;endif
  meta=struct('value_kind','number','value_format','','decimal_separator','.','unit','','time_origin','');
  if(isfield(chunk,'schema'))
    for j=1:numel(chunk.schema)
      if(strcmp(chunk.schema(j).name,name)||strcmp(chunk.schema(j).variable_id,name)),meta=chunk.schema(j);break;endif
    endfor
  endif
  for i=1:numel(c),v(i)=gxtxt_table_value_numeric(c{i},meta);endfor
endfunction
