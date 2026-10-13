% SPDX-License-Identifier: GPL-3.0-or-later
function metadata=gxtxt_table_stream_metadata(S)
  if(!isstruct(S)||!isfield(S,'api_version')),error('GXTXT:TableStream','Invalid stream');endif
  if(S.api_version>=3&&isfield(S,'metadata')),metadata=S.metadata;return;endif
  metadata=struct('api_version',S.api_version,'path',S.path,'variables',S.schema,'chunk_rows',S.chunk_rows);
endfunction
