% SPDX-License-Identifier: GPL-3.0-or-later
function v=gxtxt_table_chunk_column(chunk,name)
  if(isfield(chunk,'schema'))
    for j=1:numel(chunk.schema)
      if(strcmp(chunk.schema(j).variable_id,name)),name=chunk.schema(j).name;break;endif
    endfor
  endif
  k=find(strcmp(chunk.names,name),1);if(isempty(k)),error('GXTXT:TableStream','Chunk column not found: %s',name);endif;v=chunk.values{k};
endfunction
