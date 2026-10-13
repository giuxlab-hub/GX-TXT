% SPDX-License-Identifier: GPL-3.0-or-later
% Open an Analysis Source by its runtime Dataset ID without registry discovery.
function S=gxtxt_table_stream_open_source(runtime,source_id,variable_ids,chunk_rows,options)
  if(ischar(runtime)),runtime=gxtxt_ini_read(runtime);endif
  if(nargin<3),variable_ids={};endif;if(nargin<4),chunk_rows=5000;endif;if(nargin<5),options=struct();endif
  session=gxtxt_ini_get(runtime,'runtime.session','');
  dataset_id=gxtxt_ini_get(runtime,['analysis_source.' source_id '.dataset_id'],'');
  if(isempty(strtrim(session))),error('GXTXT:TableStream','Runtime does not provide the session path');endif
  if(isempty(strtrim(dataset_id))),error('GXTXT:TableStream','Runtime has no Analysis Source %s Dataset ID',source_id);endif
  S=gxtxt_table_stream_open_dataset(session,dataset_id,variable_ids,chunk_rows,options);
endfunction
